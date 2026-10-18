'use strict';

const LEVEL_TIME = 30;     // seconds per level
const PIECE_SIZE = 0.15;   // piece/hole width as a fraction of the board (matches CSS)
const HOLE_GAP = 0.19;     // center-to-center spacing of holes
const RING_RADIUS = 0.39;  // distance of pieces from the board center
const DRAG_THRESHOLD = 6;  // px of movement before a press counts as a drag

const board = document.getElementById('board');
const levelEl = document.getElementById('level');
const scoreEl = document.getElementById('score');
const holeSelect = document.getElementById('hole-count');
const timerBar = document.getElementById('timer-bar');
const timerText = document.getElementById('timer-text');
const toast = document.getElementById('toast');

let holeCount = Number(holeSelect.value);
let levelNum = 0;
let score = 0;
let holes = [];
let pieces = [];
let selected = null;
let drag = null;
let deadline = 0;
let transitioning = false;

// ---------- Shapes ----------
// Each generator returns an SVG path in a 100x100 box centered on (50, 50).

const rand = (a, b) => a + Math.random() * (b - a);
const r1 = n => Math.round(n * 10) / 10;
const poly = points => 'M' + points.map(([x, y]) => `${r1(x)} ${r1(y)}`).join(' L') + ' Z';

function radial(radii, start = -90) {
  return radii.map((r, i) => {
    const t = (start + (360 * i) / radii.length) * Math.PI / 180;
    return [50 + r * Math.cos(t), 50 + r * Math.sin(t)];
  });
}

const ngon = n => poly(radial(Array(n).fill(46)));

const SHAPES = {
  triangle: () => poly([[50, 6], [94, 84], [6, 84]]),
  square: () => poly([[16, 16], [84, 16], [84, 84], [16, 84]]),
  rectangle: () => {
    const h = rand(16, 22);
    return poly([[6, 50 - h], [94, 50 - h], [94, 50 + h], [6, 50 + h]]);
  },
  pentagon: () => ngon(5),
  hexagon: () => ngon(6),
  octagon: () => ngon(8),
  star: () => {
    const points = 4 + Math.floor(Math.random() * 3);
    const inner = rand(18, 24);
    return poly(radial(Array.from({ length: points * 2 }, (_, i) => (i % 2 ? inner : 48))));
  },
  cross: () => {
    const t = rand(12, 16);
    const a = 50 - t, b = 50 + t;
    return poly([[a, 4], [b, 4], [b, a], [96, a], [96, b], [b, b], [b, 96], [a, 96], [a, b], [4, b], [4, a], [a, a]]);
  },
  diamond: () => {
    const w = rand(26, 32);
    return poly([[50, 4], [50 + w, 50], [50, 96], [50 - w, 50]]);
  },
  trapezoid: () => {
    const top = rand(14, 24);
    return poly([[50 - top, 22], [50 + top, 22], [94, 78], [6, 78]]);
  },
  arrow: () => poly([[6, 38], [56, 38], [56, 14], [94, 50], [56, 86], [56, 62], [6, 62]]),
  lShape: () => poly([[16, 6], [44, 6], [44, 66], [86, 66], [86, 94], [16, 94]]),
  tShape: () => poly([[6, 8], [94, 8], [94, 36], [64, 36], [64, 94], [36, 94], [36, 36], [6, 36]]),
  heart: () => 'M50 90 C14 64 2 40 14 22 C26 6 46 10 50 28 C54 10 74 6 86 22 C98 40 86 64 50 90 Z',
  crescent: () => 'M66 4 A48 48 0 1 0 66 96 A52 52 0 0 1 66 4 Z',
  ellipse: () => {
    const ry = rand(22, 30);
    return `M4 50 A46 ${r1(ry)} 0 1 0 96 50 A46 ${r1(ry)} 0 1 0 4 50 Z`;
  },
  blob: () => poly(radial(Array.from({ length: 7 }, () => rand(26, 47)), rand(0, 360))),
};

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// Distinct shape families per level so every piece fits exactly one hole.
function pickShapes(n) {
  return shuffle(Object.keys(SHAPES)).slice(0, n).map(name => ({
    name,
    d: SHAPES[name](),
    rot: Math.floor(rand(0, 360)),
  }));
}

function shapeSvg(shape) {
  return `<svg viewBox="0 0 100 100" aria-hidden="true">` +
    `<path d="${shape.d}" transform="rotate(${shape.rot} 50 50)"/></svg>`;
}

// ---------- Layout ----------

function holeLayout(n) {
  const rows = { 2: [2], 3: [3], 4: [2, 2], 5: [3, 2] }[n];
  const positions = [];
  rows.forEach((count, r) => {
    const y = 0.5 + (r - (rows.length - 1) / 2) * HOLE_GAP;
    for (let i = 0; i < count; i++) {
      positions.push({ x: 0.5 + (i - (count - 1) / 2) * HOLE_GAP, y });
    }
  });
  return shuffle(positions);
}

function ringLayout(n) {
  const offset = rand(0, Math.PI * 2);
  return shuffle(Array.from({ length: n }, (_, i) => {
    const t = offset + (i * Math.PI * 2) / n;
    return { x: 0.5 + RING_RADIUS * Math.cos(t), y: 0.5 + RING_RADIUS * Math.sin(t) };
  }));
}

function setPos(p, x, y, animate = true) {
  p.x = x;
  p.y = y;
  if (!animate) p.el.classList.add('no-anim');
  p.el.style.left = `${x * 100}%`;
  p.el.style.top = `${y * 100}%`;
  if (!animate) {
    void p.el.offsetWidth; // commit the jump before re-enabling transitions
    p.el.classList.remove('no-anim');
  }
}

// ---------- Level lifecycle ----------

function newLevel() {
  levelNum++;
  levelEl.textContent = levelNum;
  board.replaceChildren();
  selected = null;
  drag = null;

  const shapes = pickShapes(holeCount);
  const holeSpots = holeLayout(holeCount);
  const pieceSpots = ringLayout(holeCount);

  holes = shapes.map((shape, i) => {
    const el = document.createElement('div');
    el.className = 'hole';
    el.tabIndex = 0;
    el.setAttribute('role', 'button');
    el.setAttribute('aria-label', `${shape.name} hole`);
    el.innerHTML = shapeSvg(shape);
    el.style.left = `${holeSpots[i].x * 100}%`;
    el.style.top = `${holeSpots[i].y * 100}%`;
    board.append(el);
    const hole = { shape, el, ...holeSpots[i], filled: false };
    el.addEventListener('click', () => tapHole(hole));
    el.addEventListener('keydown', e => onKey(e, () => tapHole(hole)));
    return hole;
  });

  pieces = shapes.map((shape, i) => {
    const el = document.createElement('div');
    el.className = 'piece';
    el.tabIndex = 0;
    el.setAttribute('role', 'button');
    el.setAttribute('aria-label', `${shape.name} piece`);
    el.innerHTML = shapeSvg(shape);
    board.append(el);
    const p = { shape, el, hole: holes[i], home: pieceSpots[i], placed: false };
    setPos(p, p.home.x, p.home.y, false);
    el.addEventListener('pointerdown', e => onPointerDown(e, p));
    el.addEventListener('pointermove', onPointerMove);
    el.addEventListener('pointerup', onPointerUp);
    el.addEventListener('pointercancel', onPointerCancel);
    el.addEventListener('keydown', e => onKey(e, () => tapPiece(p)));
    return p;
  });

  deadline = performance.now() + LEVEL_TIME * 1000;
  transitioning = false;
}

function endLevel(message, delay) {
  transitioning = true;
  deselect();
  showToast(message, delay);
  setTimeout(newLevel, delay);
}

function showToast(message, duration) {
  toast.textContent = message;
  toast.classList.add('show');
  setTimeout(() => toast.classList.remove('show'), duration - 100);
}

function tick(now) {
  const remaining = Math.max(0, deadline - now);
  timerBar.style.transform = `scaleX(${remaining / (LEVEL_TIME * 1000)})`;
  timerBar.classList.toggle('low', remaining < 5000);
  timerText.textContent = `${Math.ceil(remaining / 1000)}s`;
  if (remaining === 0 && !transitioning) {
    endLevel("Time's up!", 1200);
  }
  requestAnimationFrame(tick);
}

// ---------- Matching ----------

function place(p) {
  p.placed = true;
  p.hole.filled = true;
  p.el.classList.add('placed');
  p.el.tabIndex = -1;
  p.hole.el.tabIndex = -1;
  setPos(p, p.hole.x, p.hole.y);
  if (pieces.every(q => q.placed)) {
    score++;
    scoreEl.textContent = score;
    endLevel('Level cleared!', 900);
  }
}

function reject(p, hole) {
  for (const el of [p.el, hole.el]) {
    el.classList.remove('shake');
    void el.offsetWidth; // restart the animation
    el.classList.add('shake');
    el.addEventListener('animationend', () => el.classList.remove('shake'), { once: true });
  }
  setPos(p, p.home.x, p.home.y);
}

function select(p) {
  deselect();
  selected = p;
  p.el.classList.add('selected');
}

function deselect() {
  if (selected) selected.el.classList.remove('selected');
  selected = null;
}

// ---------- Tap-tap ----------

function tapPiece(p) {
  if (p.placed || transitioning) return;
  if (selected === p) deselect();
  else select(p);
}

function tapHole(hole) {
  if (!selected || hole.filled || transitioning) return;
  const p = selected;
  deselect();
  if (p.hole === hole) place(p);
  else reject(p, hole);
}

function onKey(e, action) {
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    action();
  }
}

// ---------- Drag and drop ----------

function onPointerDown(e, p) {
  if (p.placed || transitioning || drag) return;
  e.preventDefault();
  p.el.setPointerCapture(e.pointerId);
  drag = { p, id: e.pointerId, sx: e.clientX, sy: e.clientY, dx: 0, dy: 0, moved: false };
}

function onPointerMove(e) {
  if (!drag || e.pointerId !== drag.id) return;
  drag.dx = e.clientX - drag.sx;
  drag.dy = e.clientY - drag.sy;
  if (!drag.moved && Math.hypot(drag.dx, drag.dy) > DRAG_THRESHOLD) {
    drag.moved = true;
    drag.p.el.classList.add('dragging');
    deselect();
  }
  if (drag.moved) {
    drag.p.el.style.transform = `translate(calc(-50% + ${drag.dx}px), calc(-50% + ${drag.dy}px))`;
  }
}

function onPointerUp(e) {
  if (!drag || e.pointerId !== drag.id) return;
  const { p, dx, dy, moved } = drag;
  drag = null;
  if (!moved) {
    tapPiece(p);
    return;
  }

  // Swap the drag transform for an equivalent position, so the piece animates from where it was dropped.
  const rect = board.getBoundingClientRect();
  const x = p.x + dx / rect.width;
  const y = p.y + dy / rect.height;
  p.el.classList.remove('dragging');
  p.el.style.transform = '';
  setPos(p, x, y, false);

  if (transitioning) {
    setPos(p, p.home.x, p.home.y);
    return;
  }

  const target = holes
    .filter(h => !h.filled)
    .map(h => ({ h, dist: Math.hypot(h.x - x, h.y - y) }))
    .filter(({ dist }) => dist < PIECE_SIZE * 0.6)
    .sort((a, b) => a.dist - b.dist)[0];

  if (!target) setPos(p, p.home.x, p.home.y);
  else if (target.h === p.hole) place(p);
  else reject(p, target.h);
}

function onPointerCancel(e) {
  if (!drag || e.pointerId !== drag.id) return;
  const { p } = drag;
  drag = null;
  p.el.classList.remove('dragging');
  p.el.style.transform = '';
}

// ---------- Start ----------

holeSelect.addEventListener('change', () => {
  holeCount = Number(holeSelect.value);
  levelNum = 0;
  score = 0;
  scoreEl.textContent = score;
  newLevel();
});

newLevel();
requestAnimationFrame(tick);
