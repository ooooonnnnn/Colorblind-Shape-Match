"""Generates cover.svg (1260x1000, 2x the itch.io 630x500 cover size)."""
import math

W, H = 1260, 1000
CX, CY = 630, 500
CORAL = "#ff7a59"
CORAL_D = "#c4472a"
CORAL_L = "#ffb199"


def regular(n, start=0.0):
    return [(math.cos(start + i * 2 * math.pi / n), math.sin(start + i * 2 * math.pi / n)) for i in range(n)]


def star():
    pts = []
    for i in range(10):
        r = 1.0 if i % 2 == 0 else 0.45
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


def cross():
    t = 0.34
    return [(-t, -1), (t, -1), (t, -t), (1, -t), (1, t), (t, t), (t, 1), (-t, 1), (-t, t), (-1, t), (-1, -t), (-t, -t)]


def heart():
    pts = []
    for i in range(48):
        a = i * 2 * math.pi / 48
        x = 16 * math.sin(a) ** 3
        y = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
        pts.append((x / 17, y / 17))
    return pts


SHAPES = {
    "circle": regular(40),
    "triangle": regular(3, -math.pi / 2),
    "square": regular(4, math.pi / 4),
    "hexagon": regular(6),
    "star": star(),
    "cross": cross(),
    "heart": heart(),
}


def poly(name, x, y, s, rot=0.0):
    c, sn = math.cos(rot), math.sin(rot)
    return " ".join(f"{x + (px * c - py * sn) * s:.1f},{y + (px * sn + py * c) * s:.1f}" for px, py in SHAPES[name])


out = []
a = out.append
a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
a('''<defs>
<radialGradient id="bg" cx="50%" cy="50%" r="75%"><stop offset="0" stop-color="#2a2d44"/><stop offset="1" stop-color="#0d0e16"/></radialGradient>
<radialGradient id="iris" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#3b4270"/><stop offset="0.7" stop-color="#262b4f"/><stop offset="1" stop-color="#171a33"/></radialGradient>
<linearGradient id="sclera" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e9e6f2"/><stop offset="1" stop-color="#bdb9d0"/></linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="10" stdDeviation="9" flood-color="#000" flood-opacity="0.55"/></filter>
<clipPath id="eyeclip"><path d="M70 500 Q630 90 1190 500 Q630 910 70 500 Z"/></clipPath>
</defs>''')
a(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>')

# faint background shape confetti (dark holes echoing the game)
import random
random.seed(7)
names = list(SHAPES)
for _ in range(34):
    x, y = random.uniform(30, W - 30), random.uniform(30, H - 30)
    if abs(x - CX) < 600 and abs(y - CY) < 260 and (x - CX) ** 2 / 600 ** 2 + (y - CY) ** 2 / 260 ** 2 < 1.0:
        continue
    n = random.choice(names)
    a(f'<polygon points="{poly(n, x, y, random.uniform(22, 44), random.uniform(0, 6.28))}" fill="#090a10" stroke="#3a3e5c" stroke-width="2" opacity="0.85"/>')

# eye
a(f'<path d="M70 500 Q630 90 1190 500 Q630 910 70 500 Z" fill="url(#sclera)" stroke="#07080d" stroke-width="10"/>')
a('<g clip-path="url(#eyeclip)">')
a(f'<circle cx="{CX}" cy="{CY}" r="270" fill="url(#iris)" stroke="#0a0b14" stroke-width="8"/>')
for i in range(72):  # iris fibres
    ang = i * 2 * math.pi / 72
    a(f'<line x1="{CX + math.cos(ang) * 150:.1f}" y1="{CY + math.sin(ang) * 150:.1f}" x2="{CX + math.cos(ang) * 262:.1f}" y2="{CY + math.sin(ang) * 262:.1f}" stroke="#4b538a" stroke-width="2.5" opacity="0.35"/>')
# lid shadow
a(f'<path d="M70 500 Q630 90 1190 500 L1190 300 L70 300 Z" fill="#000" opacity="0.18"/>')
a('</g>')
a(f'<path d="M70 500 Q630 90 1190 500 Q630 910 70 500 Z" fill="none" stroke="#07080d" stroke-width="10"/>')

# shaped holes in the iris ring + pupil hole
ring = ["triangle", "heart", "cross", "square", "hexagon"]
holes = []
for i, n in enumerate(ring):
    ang = -math.pi / 2 + i * 2 * math.pi / 5 + 0.0
    x, y = CX + math.cos(ang) * 175, CY + math.sin(ang) * 175
    holes.append((n, x, y))
    a(f'<polygon points="{poly(n, x, y, 52)}" fill="#05060b" stroke="#6c74b3" stroke-width="4" stroke-linejoin="round"/>')
a(f'<polygon points="{poly("star", CX, CY, 78)}" fill="#05060b" stroke="#6c74b3" stroke-width="4" stroke-linejoin="round"/>')

# pieces: one already seated (pupil star), one half way in, the rest orbiting
def piece(n, x, y, s, rot, lift=True):
    f = ' filter="url(#sh)"' if lift else ""
    return (f'<g{f}><polygon points="{poly(n, x, y, s, rot)}" fill="{CORAL}" stroke="{CORAL_D}" stroke-width="5" stroke-linejoin="round"/>'
            f'<polygon points="{poly(n, x - 3, y - 4, s * 0.7, rot)}" fill="{CORAL_L}" opacity="0.28"/></g>')

a(piece("star", CX, CY, 78, 0, lift=False))  # seated in the pupil
n, x, y = holes[2]
a(piece("cross", x, y, 52, 0, lift=False))   # seated
n, x, y = holes[1]
a(piece("heart", x + 40, y - 120, 56, -0.35))  # about to drop in
# flying pieces around the eye
a(piece("triangle", 150, 190, 74, 0.35))
a(piece("square", 1090, 205, 68, 0.5))
a(piece("hexagon", 1105, 800, 72, 0.2))
a(piece("circle", 175, 795, 66, 0))
a(piece("triangle", 640, 905, 0, 0)) if False else None
a(piece("square", 640, 100, 0, 0)) if False else None
# motion trails (dashed arcs) hinting at pieces flying in
for (x1, y1, x2, y2) in [(190, 235, 360, 420), (1050, 250, 905, 420), (1065, 760, 880, 600), (215, 755, 385, 610)]:
    a(f'<path d="M{x1} {y1} Q{(x1 + x2) / 2 + 20} {(y1 + y2) / 2 - 40} {x2} {y2}" fill="none" stroke="{CORAL}" stroke-width="5" stroke-dasharray="4 16" stroke-linecap="round" opacity="0.7"/>')

# eye highlight
a(f'<ellipse cx="{CX - 95}" cy="{CY - 120}" rx="34" ry="20" fill="#fff" opacity="0.22" transform="rotate(-30 {CX - 95} {CY - 120})"/>')
a('</svg>')
open("cover.svg", "w").write("\n".join(x for x in out if x))
