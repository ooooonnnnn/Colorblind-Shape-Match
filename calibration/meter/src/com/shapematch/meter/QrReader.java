package com.shapematch.meter;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Reads a QR code from a camera picture's brightness, so the meter can scan
 * the code the game shows without any library: plain Java, no Android
 * classes, so it can be tested on a computer.
 *
 * It handles what Shape Match's code needs (scripts/qr_code.gd makes byte
 * mode, versions 1 to 9) and a little more: versions 1 to 10 at any error
 * correction level, byte mode. The steps are the standard's: a local
 * threshold, the three finder patterns (1:1:3:1:1 runs), the alignment
 * pattern for perspective, the module grid sampled, format and version
 * information read, the mask removed, codewords read and corrected by
 * Reed-Solomon, then the bytes read out.
 */
public final class QrReader {
	private QrReader() {}

	// Per version (1-10), per level in format order (M, L, H, Q, the two bits
	// the format information holds): error codewords per block, then pairs of
	// (number of blocks, data codewords in each).
	private static final int[][][] BLOCKS = {
		{{10, 1, 16}, {7, 1, 19}, {17, 1, 9}, {13, 1, 13}},
		{{16, 1, 28}, {10, 1, 34}, {28, 1, 16}, {22, 1, 22}},
		{{26, 1, 44}, {15, 1, 55}, {22, 2, 13}, {18, 2, 17}},
		{{18, 2, 32}, {20, 1, 80}, {16, 4, 9}, {26, 2, 24}},
		{{24, 2, 43}, {26, 1, 108}, {22, 2, 11, 2, 12}, {18, 2, 15, 2, 16}},
		{{16, 4, 27}, {18, 2, 68}, {28, 4, 15}, {24, 4, 19}},
		{{18, 4, 31}, {20, 2, 78}, {26, 4, 13, 1, 14}, {18, 2, 14, 4, 15}},
		{{22, 2, 38, 2, 39}, {24, 2, 97}, {26, 4, 14, 2, 15}, {22, 4, 18, 2, 19}},
		{{22, 3, 36, 2, 37}, {30, 2, 116}, {24, 4, 12, 4, 13}, {20, 4, 16, 4, 17}},
		{{26, 4, 43, 1, 44}, {18, 2, 68, 2, 69}, {28, 6, 15, 2, 16}, {24, 6, 19, 2, 20}},
	};
	private static final int[][] ALIGNMENT = {
		{}, {6, 18}, {6, 22}, {6, 26}, {6, 30}, {6, 34}, {6, 22, 38}, {6, 24, 42}, {6, 26, 46}, {6, 28, 50},
	};

	/** The text in the clearest QR code in a picture of width x height brightness values (row by row), or null. */
	public static String read(byte[] luma, int width, int height, int rowStride) {
		boolean[] dark = threshold(luma, width, height, rowStride);
		List<float[]> centers = findFinders(dark, width, height);
		if (centers.size() < 3) return null;
		// Every set of three finders that could be one code, best shaped first.
		List<float[][]> triples = new ArrayList<>();
		for (int a = 0; a < centers.size(); a++) {
			for (int b = a + 1; b < centers.size(); b++) {
				for (int c = b + 1; c < centers.size(); c++) {
					float[][] t = order(centers.get(a), centers.get(b), centers.get(c));
					if (t != null) triples.add(t);
				}
			}
		}
		triples.sort((x, y) -> Float.compare(x[3][0], y[3][0]));
		for (int i = 0; i < Math.min(triples.size(), 6); i++) {
			String text = decodeAt(dark, width, height, triples.get(i));
			if (text != null) return text;
		}
		return null;
	}

	// ---------- Finding the code ----------

	/** Dark pixels: darker than the mean around them (a window an eighth of the picture across). */
	private static boolean[] threshold(byte[] luma, int w, int h, int stride) {
		long[] sum = new long[(w + 1) * (h + 1)];
		for (int y = 0; y < h; y++) {
			long row = 0;
			for (int x = 0; x < w; x++) {
				row += luma[y * stride + x] & 0xFF;
				sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + row;
			}
		}
		int r = Math.max(8, Math.min(w, h) / 16);
		boolean[] dark = new boolean[w * h];
		for (int y = 0; y < h; y++) {
			int y0 = Math.max(0, y - r), y1 = Math.min(h, y + r + 1);
			for (int x = 0; x < w; x++) {
				int x0 = Math.max(0, x - r), x1 = Math.min(w, x + r + 1);
				long total = sum[y1 * (w + 1) + x1] - sum[y0 * (w + 1) + x1] - sum[y1 * (w + 1) + x0] + sum[y0 * (w + 1) + x0];
				int area = (x1 - x0) * (y1 - y0);
				dark[y * w + x] = (luma[y * stride + x] & 0xFF) * area < total - 6L * area;
			}
		}
		return dark;
	}

	/** Finder pattern centers, {x, y, module size, times seen}. */
	private static List<float[]> findFinders(boolean[] dark, int w, int h) {
		List<float[]> found = new ArrayList<>();
		int[] runs = new int[5];
		for (int y = 0; y < h; y += 2) {
			int state = 0;
			java.util.Arrays.fill(runs, 0);
			for (int x = 0; x < w; x++) {
				boolean d = dark[y * w + x];
				if (d == ((state & 1) == 0)) {
					runs[state]++;
				} else if (state == 0 && runs[0] == 0) {
					continue;  // a pattern starts with dark
				} else if (state < 4) {
					runs[++state] = 1;
				} else {
					if (isFinder(runs)) check(dark, w, h, x - runs[4] - runs[3] - runs[2] / 2f, y, runs, found);
					// The last dark, light, dark may begin the next pattern.
					runs[0] = runs[2];
					runs[1] = runs[3];
					runs[2] = runs[4];
					runs[3] = 1;
					runs[4] = 0;
					state = 3;
				}
			}
			if (state == 4 && isFinder(runs)) check(dark, w, h, w - runs[4] - runs[3] - runs[2] / 2f, y, runs, found);
		}
		List<float[]> sure = new ArrayList<>();
		for (float[] f : found) if (f[3] >= 2) sure.add(f);
		return sure.size() >= 3 ? sure : found;
	}

	private static boolean isFinder(int[] runs) {
		int total = 0;
		for (int r : runs) {
			if (r == 0) return false;
			total += r;
		}
		if (total < 7) return false;
		float module = total / 7f, slack = module / 1.6f;
		return Math.abs(module - runs[0]) < slack && Math.abs(module - runs[1]) < slack && Math.abs(3 * module - runs[2]) < 3 * slack
			&& Math.abs(module - runs[3]) < slack && Math.abs(module - runs[4]) < slack;
	}

	/** Confirms a possible finder across, refines its center, and adds it or merges it with one found before. */
	private static void check(boolean[] dark, int w, int h, float cx, int y, int[] runs, List<float[]> found) {
		int total = runs[0] + runs[1] + runs[2] + runs[3] + runs[4];
		float cy = cross(dark, w, h, (int) cx, y, 0, 1, total);
		if (Float.isNaN(cy)) return;
		float cx2 = cross(dark, w, h, (int) cx, (int) cy, 1, 0, total);
		if (Float.isNaN(cx2)) return;
		float cy2 = cross(dark, w, h, (int) cx2, (int) cy, 0, 1, total);
		if (Float.isNaN(cy2)) return;
		float module = total / 7f;
		for (float[] f : found) {
			if (Math.abs(f[0] - cx2) <= module * 1.5f && Math.abs(f[1] - cy2) <= module * 1.5f && Math.abs(f[2] - module) <= Math.max(1, module / 2)) {
				float n = f[3];
				f[0] = (f[0] * n + cx2) / (n + 1);
				f[1] = (f[1] * n + cy2) / (n + 1);
				f[2] = (f[2] * n + module) / (n + 1);
				f[3] = n + 1;
				return;
			}
		}
		found.add(new float[] {cx2, cy2, module, 1});
	}

	/** Along (dx, dy) through (x, y): the middle of a 1:1:3:1:1 pattern of about total pixels, or NaN. */
	private static float cross(boolean[] dark, int w, int h, int x, int y, int dx, int dy, int total) {
		if (x < 0 || y < 0 || x >= w || y >= h || !dark[y * w + x]) return Float.NaN;
		int[] runs = new int[5];
		int i = 0;
		// Back from the middle: the center's dark run, then light, then dark.
		while (inside(x - dx * i, y - dy * i, w, h) && dark[(y - dy * i) * w + x - dx * i]) { runs[2]++; i++; }
		while (inside(x - dx * i, y - dy * i, w, h) && !dark[(y - dy * i) * w + x - dx * i]) { runs[1]++; i++; }
		while (inside(x - dx * i, y - dy * i, w, h) && dark[(y - dy * i) * w + x - dx * i]) { runs[0]++; i++; }
		int back = runs[2];  // the center run's pixels from (x, y) back
		i = 1;
		while (inside(x + dx * i, y + dy * i, w, h) && dark[(y + dy * i) * w + x + dx * i]) { runs[2]++; i++; }
		while (inside(x + dx * i, y + dy * i, w, h) && !dark[(y + dy * i) * w + x + dx * i]) { runs[3]++; i++; }
		while (inside(x + dx * i, y + dy * i, w, h) && dark[(y + dy * i) * w + x + dx * i]) { runs[4]++; i++; }
		int sum = runs[0] + runs[1] + runs[2] + runs[3] + runs[4];
		if (Math.abs(sum - total) > total || !isFinder(runs)) return Float.NaN;
		int at = dx != 0 ? x : y;
		int first = at - (back - 1), last = at + (runs[2] - back);
		return (first + last + 1) / 2f;  // pixel i covers i to i + 1
	}

	private static boolean inside(int x, int y, int w, int h) {
		return x >= 0 && y >= 0 && x < w && y < h;
	}

	/**
	 * Three finders as {top left, top right, bottom left, {badness}}: the top
	 * left is at the right angle; null when they can't be one code.
	 */
	private static float[][] order(float[] a, float[] b, float[] c) {
		float module = (a[2] + b[2] + c[2]) / 3;
		float smallest = Math.min(a[2], Math.min(b[2], c[2])), largest = Math.max(a[2], Math.max(b[2], c[2]));
		if (largest > smallest * 1.5f) return null;  // finders of one code are the same size
		float ab = dist(a, b), bc = dist(b, c), ac = dist(a, c);
		float[] corner, p, q;
		if (bc >= ab && bc >= ac) { corner = a; p = b; q = c; }
		else if (ac >= ab && ac >= bc) { corner = b; p = a; q = c; }
		else { corner = c; p = a; q = b; }
		float d1 = dist(corner, p), d2 = dist(corner, q);
		if (d1 < module * 11 || d2 < module * 11) return null;  // closer than a version 1 code's 14 modules
		float sides = Math.abs(d1 - d2) / Math.max(d1, d2);
		float cos = ((p[0] - corner[0]) * (q[0] - corner[0]) + (p[1] - corner[1]) * (q[1] - corner[1])) / (d1 * d2);
		if (sides > 0.3f || Math.abs(cos) > 0.3f) return null;
		// Top right is clockwise from top left's other neighbor.
		float z = (p[0] - corner[0]) * (q[1] - corner[1]) - (p[1] - corner[1]) * (q[0] - corner[0]);
		float[] right = z > 0 ? p : q, left = z > 0 ? q : p;
		return new float[][] {corner, right, left, {sides + Math.abs(cos)}};
	}

	private static float dist(float[] a, float[] b) {
		return (float) Math.hypot(a[0] - b[0], a[1] - b[1]);
	}

	// ---------- Reading it ----------

	private static String decodeAt(boolean[] dark, int w, int h, float[][] t) {
		float[] tl = t[0], tr = t[1], bl = t[2];
		float module = (tl[2] + tr[2] + bl[2]) / 3;
		int across = Math.round((dist(tl, tr) / module + dist(tl, bl) / module) / 2) + 7;
		int guess = across;
		switch (across & 3) {
			case 0: guess = across + 1; break;
			case 2: guess = across - 1; break;
			case 3: guess = across - 2; break;
			default: break;
		}
		for (int size : new int[] {guess, guess + 4, guess - 4}) {
			int version = (size - 17) / 4;
			if (version < 1 || version > BLOCKS.length) continue;
			String text = decodeGrid(dark, w, h, tl, tr, bl, version);
			if (text != null) return text;
		}
		return null;
	}

	private static String decodeGrid(boolean[] dark, int w, int h, float[] tl, float[] tr, float[] bl, int version) {
		int size = 17 + 4 * version;
		float brX = tr[0] - tl[0] + bl[0], brY = tr[1] - tl[1] + bl[1];
		// The bottom right alignment pattern (three modules in from where a
		// fourth finder would be) fixes perspective; without it, the corner
		// is taken as the parallelogram's.
		List<float[]> corners = new ArrayList<>();
		if (version >= 2) {
			float share = 1 - 3f / (size - 7);
			float[] found = findAlignment(dark, w, h, tl[0] + share * (brX - tl[0]), tl[1] + share * (brY - tl[1]), (tl[2] + tr[2] + bl[2]) / 3);
			if (found != null) corners.add(new float[] {found[0], found[1], size - 6.5f});
		}
		corners.add(new float[] {brX, brY, size - 3.5f});
		for (float[] corner : corners) {
			String text = sample(dark, w, h, tl, tr, bl, corner, size);
			if (text != null) return text;
		}
		return null;
	}

	private static String sample(boolean[] dark, int w, int h, float[] tl, float[] tr, float[] bl, float[] corner, int size) {
		float cornerAt = corner[2];
		double[] map = homography(new double[] {3.5, 3.5, size - 3.5, 3.5, 3.5, size - 3.5, cornerAt, cornerAt},
			new double[] {tl[0], tl[1], tr[0], tr[1], bl[0], bl[1], corner[0], corner[1]});
		if (map == null) return null;
		boolean[][] grid = new boolean[size][size];
		for (int y = 0; y < size; y++) {
			for (int x = 0; x < size; x++) {
				double u = x + 0.5, v = y + 0.5;
				double d = map[6] * u + map[7] * v + 1;
				int px = (int) Math.floor((map[0] * u + map[1] * v + map[2]) / d);
				int py = (int) Math.floor((map[3] * u + map[4] * v + map[5]) / d);
				if (!inside(px, py, w, h)) return null;
				grid[y][x] = dark[py * w + px];
			}
		}
		return decodeModules(grid);
	}

	/** An alignment pattern's center (dark, light ring, dark ring) near (x, y), or null. */
	private static float[] findAlignment(boolean[] dark, int w, int h, float x, float y, float module) {
		int reach = (int) (module * 5);
		float[] best = null;
		float bestDistance = Float.MAX_VALUE;
		for (int dy = -reach; dy <= reach; dy++) {
			int py = Math.round(y) + dy;
			if (py < 0 || py >= h) continue;
			for (int dx = -reach; dx <= reach; dx++) {
				int px = Math.round(x) + dx;
				if (!inside(px, py, w, h) || !dark[py * w + px]) continue;
				// A dark middle about a module wide, light all round it, dark beyond.
				if (!ring(dark, w, h, px, py, module)) continue;
				float distance = dx * dx + dy * dy;
				if (distance < bestDistance) {
					bestDistance = distance;
					best = new float[] {px, py};
				}
			}
		}
		if (best == null) return null;
		// The middle of the dark spot found.
		float sx = 0, sy = 0;
		int n = 0;
		int r = Math.max(1, (int) (module * 0.7f));
		for (int dy = -r; dy <= r; dy++) {
			for (int dx = -r; dx <= r; dx++) {
				int px = (int) best[0] + dx, py = (int) best[1] + dy;
				if (inside(px, py, w, h) && dark[py * w + px]) { sx += px; sy += py; n++; }
			}
		}
		return n > 0 ? new float[] {sx / n + 0.5f, sy / n + 0.5f} : best;
	}

	private static boolean ring(boolean[] dark, int w, int h, int x, int y, float module) {
		int[][] directions = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
		for (int[] d : directions) {
			int light = Math.round(module * 1.0f), far = Math.round(module * 2.0f);
			int lx = x + d[0] * light, ly = y + d[1] * light, fx = x + d[0] * far, fy = y + d[1] * far;
			if (!inside(fx, fy, w, h) || dark[ly * w + lx] || !dark[fy * w + fx]) return false;
		}
		return true;
	}

	/** The 3x3 map (8 numbers, last one 1) taking module coordinates to picture ones. */
	private static double[] homography(double[] from, double[] to) {
		double[][] m = new double[8][9];
		for (int i = 0; i < 4; i++) {
			double u = from[2 * i], v = from[2 * i + 1], x = to[2 * i], y = to[2 * i + 1];
			m[2 * i] = new double[] {u, v, 1, 0, 0, 0, -u * x, -v * x, x};
			m[2 * i + 1] = new double[] {0, 0, 0, u, v, 1, -u * y, -v * y, y};
		}
		for (int col = 0; col < 8; col++) {
			int pivot = col;
			for (int row = col + 1; row < 8; row++) if (Math.abs(m[row][col]) > Math.abs(m[pivot][col])) pivot = row;
			if (Math.abs(m[pivot][col]) < 1e-12) return null;
			double[] swap = m[col];
			m[col] = m[pivot];
			m[pivot] = swap;
			for (int row = 0; row < 8; row++) {
				if (row == col) continue;
				double f = m[row][col] / m[col][col];
				for (int k = col; k < 9; k++) m[row][k] -= f * m[col][k];
			}
		}
		double[] out = new double[8];
		for (int i = 0; i < 8; i++) out[i] = m[i][8] / m[i][i];
		return out;
	}

	/** The text in a sampled grid of modules (true for dark), or null. */
	static String decodeModules(boolean[][] grid) {
		int size = grid.length;
		int version = (size - 17) / 4;
		if (version >= 7) {
			int read = 0;
			for (int y = 5; y >= 0; y--) for (int x = size - 9; x >= size - 11; x--) read = (read << 1) | (grid[y][x] ? 1 : 0);
			int best = -1, bestDistance = 4;
			for (int v = 7; v <= BLOCKS.length; v++) {
				int distance = Integer.bitCount(read ^ versionCode(v));
				if (distance < bestDistance) { bestDistance = distance; best = v; }
			}
			if (best != version) return null;
		}
		int format = readFormat(grid);
		if (format < 0) return null;
		int level = format >> 3, mask = format & 7;
		boolean[][] reserved = functionPatterns(version);
		// The codewords, two columns at a time from the right, up and down in turn.
		int total = 0;
		for (int[] b : levelBlocks(version, level)) total += b[1] * (b[0] + b[2]);
		byte[] raw = new byte[total];
		int bit = 0;
		boolean upward = true;
		for (int right = size - 1; right > 0; right -= 2) {
			if (right == 6) right--;
			for (int k = 0; k < size; k++) {
				int y = upward ? size - 1 - k : k;
				for (int c = 0; c < 2; c++) {
					int x = right - c;
					if (reserved[y][x]) continue;
					boolean dark = grid[y][x] ^ masked(mask, y, x);
					if (bit / 8 < total && dark) raw[bit / 8] |= (byte) (0x80 >> (bit % 8));
					bit++;
				}
			}
			upward = !upward;
		}
		byte[] data = correct(raw, version, level);
		return data == null ? null : readBytes(data, version);
	}

	/** {error codewords, blocks, data codewords} per block group. */
	private static List<int[]> levelBlocks(int version, int level) {
		int[] row = BLOCKS[version - 1][level];
		List<int[]> groups = new ArrayList<>();
		for (int i = 1; i < row.length; i += 2) groups.add(new int[] {row[0], row[i], row[i + 1]});
		return groups;
	}

	private static int versionCode(int version) {
		int rem = version << 12;
		for (int i = 17; i >= 12; i--) if (((rem >> i) & 1) != 0) rem ^= 0x1F25 << (i - 12);
		return (version << 12) | rem;
	}

	/** The format information's five bits (level, then mask) from either copy, or -1. */
	private static int readFormat(boolean[][] grid) {
		int size = grid.length;
		int first = 0, second = 0;
		for (int x = 0; x <= 5; x++) first = (first << 1) | bit(grid, x, 8);
		first = (first << 1) | bit(grid, 7, 8);
		first = (first << 1) | bit(grid, 8, 8);
		first = (first << 1) | bit(grid, 8, 7);
		for (int y = 5; y >= 0; y--) first = (first << 1) | bit(grid, 8, y);
		for (int y = size - 1; y >= size - 7; y--) second = (second << 1) | bit(grid, 8, y);
		for (int x = size - 8; x < size; x++) second = (second << 1) | bit(grid, x, 8);
		int best = -1, bestDistance = 4;
		for (int data = 0; data < 32; data++) {
			int rem = data << 10;
			for (int i = 14; i >= 10; i--) if (((rem >> i) & 1) != 0) rem ^= 0x537 << (i - 10);
			int code = ((data << 10) | rem) ^ 0x5412;
			int distance = Math.min(Integer.bitCount(code ^ first), Integer.bitCount(code ^ second));
			if (distance < bestDistance) { bestDistance = distance; best = data; }
		}
		return best;
	}

	private static int bit(boolean[][] grid, int x, int y) {
		return grid[y][x] ? 1 : 0;
	}

	private static boolean[][] functionPatterns(int version) {
		int size = 17 + 4 * version;
		boolean[][] r = new boolean[size][size];
		mark(r, 0, 0, 9, 9);
		mark(r, size - 8, 0, 8, 9);
		mark(r, 0, size - 8, 9, 8);
		int[] centers = ALIGNMENT[version - 1];
		for (int cy : centers) {
			for (int cx : centers) {
				boolean byFinder = (cx == 6 && cy == 6) || (cx == 6 && cy == centers[centers.length - 1]) || (cy == 6 && cx == centers[centers.length - 1]);
				if (!byFinder) mark(r, cx - 2, cy - 2, 5, 5);
			}
		}
		mark(r, 6, 9, 1, size - 17);
		mark(r, 9, 6, size - 17, 1);
		if (version >= 7) {
			mark(r, size - 11, 0, 3, 6);
			mark(r, 0, size - 11, 6, 3);
		}
		return r;
	}

	private static void mark(boolean[][] r, int x, int y, int w, int h) {
		for (int j = y; j < y + h; j++) for (int i = x; i < x + w; i++) r[j][i] = true;
	}

	private static boolean masked(int mask, int i, int j) {
		switch (mask) {
			case 0: return (i + j) % 2 == 0;
			case 1: return i % 2 == 0;
			case 2: return j % 3 == 0;
			case 3: return (i + j) % 3 == 0;
			case 4: return (i / 2 + j / 3) % 2 == 0;
			case 5: return (i * j) % 2 + (i * j) % 3 == 0;
			case 6: return ((i * j) % 2 + (i * j) % 3) % 2 == 0;
			default: return ((i + j) % 2 + (i * j) % 3) % 2 == 0;
		}
	}

	/** The data codewords, blocks taken apart and each corrected, or null when a block is past correcting. */
	private static byte[] correct(byte[] raw, int version, int level) {
		List<int[]> sizes = new ArrayList<>();  // {data, error} per block, in order
		for (int[] g : levelBlocks(version, level)) for (int i = 0; i < g[1]; i++) sizes.add(new int[] {g[2], g[0]});
		int blocks = sizes.size(), most = 0, ec = sizes.get(0)[1], dataTotal = 0;
		for (int[] s : sizes) { most = Math.max(most, s[0]); dataTotal += s[0]; }
		int[][] words = new int[blocks][];
		for (int b = 0; b < blocks; b++) words[b] = new int[sizes.get(b)[0] + ec];
		int at = 0;
		for (int i = 0; i < most; i++) for (int b = 0; b < blocks; b++) if (i < sizes.get(b)[0]) words[b][i] = raw[at++] & 0xFF;
		for (int i = 0; i < ec; i++) for (int b = 0; b < blocks; b++) words[b][sizes.get(b)[0] + i] = raw[at++] & 0xFF;
		byte[] out = new byte[dataTotal];
		int put = 0;
		for (int b = 0; b < blocks; b++) {
			if (!ReedSolomon.correct(words[b], ec)) return null;
			for (int i = 0; i < sizes.get(b)[0]; i++) out[put++] = (byte) words[b][i];
		}
		return out;
	}

	private static final String ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

	/** The segments read out: numeric, alphanumeric and bytes (UTF-8); null for anything else. */
	private static String readBytes(byte[] data, int version) {
		int[] pos = {0};
		java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
		int end = data.length * 8;
		while (pos[0] + 4 <= end) {
			int mode = bits(data, pos, 4);
			if (mode == 0) break;
			if (mode == 7) {  // ECI: a character set number, taken as UTF-8 anyway
				bits(data, pos, 8);
				continue;
			}
			if (mode == 1) {
				int count = bits(data, pos, version < 10 ? 10 : 12);
				for (; count >= 3; count -= 3) write(bytes, String.format("%03d", bits(data, pos, 10)));
				if (count == 2) write(bytes, String.format("%02d", bits(data, pos, 7)));
				else if (count == 1) write(bytes, String.valueOf(bits(data, pos, 4)));
			} else if (mode == 2) {
				int count = bits(data, pos, version < 10 ? 9 : 11);
				for (; count >= 2; count -= 2) {
					int pair = bits(data, pos, 11);
					bytes.write(ALPHANUMERIC.charAt(pair / 45));
					bytes.write(ALPHANUMERIC.charAt(pair % 45));
				}
				if (count == 1) bytes.write(ALPHANUMERIC.charAt(bits(data, pos, 6) % 45));
			} else if (mode == 4) {
				int count = bits(data, pos, version < 10 ? 8 : 16);
				for (int i = 0; i < count; i++) bytes.write(bits(data, pos, 8));
			} else {
				return null;
			}
			if (pos[0] > end) return null;
		}
		return bytes.size() > 0 ? new String(bytes.toByteArray(), StandardCharsets.UTF_8) : null;
	}

	private static void write(java.io.ByteArrayOutputStream out, String text) {
		byte[] b = text.getBytes(StandardCharsets.US_ASCII);
		out.write(b, 0, b.length);
	}

	private static int bits(byte[] data, int[] pos, int n) {
		int value = 0;
		for (int i = 0; i < n; i++) {
			int p = pos[0]++;
			value = (value << 1) | (p / 8 < data.length ? (data[p / 8] >> (7 - p % 8)) & 1 : 0);
		}
		return value;
	}

	/** Reed-Solomon over GF(256) as QR uses it (polynomial 0x11D, first root 1). */
	static final class ReedSolomon {
		private static final int[] EXP = new int[512];
		private static final int[] LOG = new int[256];
		static {
			int x = 1;
			for (int i = 0; i < 255; i++) {
				EXP[i] = x;
				LOG[x] = i;
				x <<= 1;
				if (x >= 256) x ^= 0x11D;
			}
			for (int i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
		}

		static int mul(int a, int b) {
			return a == 0 || b == 0 ? 0 : EXP[LOG[a] + LOG[b]];
		}

		static int div(int a, int b) {
			return a == 0 ? 0 : EXP[(LOG[a] - LOG[b] + 255) % 255];
		}

		/** Fixes up to ec/2 wrong codewords in word (data then error codewords) in place; false when it can't. */
		static boolean correct(int[] word, int ec) {
			int n = word.length;
			int[] syndromes = new int[ec];
			boolean clean = true;
			for (int i = 0; i < ec; i++) {
				int s = 0;
				for (int k = 0; k < n; k++) s = mul(s, EXP[i]) ^ word[k];
				syndromes[i] = s;
				if (s != 0) clean = false;
			}
			if (clean) return true;
			// Berlekamp-Massey: the error locator, lowest power first.
			int[] locator = new int[ec + 1], previous = new int[ec + 1];
			locator[0] = previous[0] = 1;
			int length = 0, shift = 1, lastDiscrepancy = 1;
			for (int r = 0; r < ec; r++) {
				int d = syndromes[r];
				for (int i = 1; i <= length; i++) d ^= mul(locator[i], syndromes[r - i]);
				if (d == 0) {
					shift++;
					continue;
				}
				int[] before = locator.clone();
				int f = div(d, lastDiscrepancy);
				for (int i = 0; i + shift <= ec; i++) locator[i + shift] ^= mul(f, previous[i]);
				if (2 * length <= r) {
					length = r + 1 - length;
					previous = before;
					lastDiscrepancy = d;
					shift = 1;
				} else {
					shift++;
				}
			}
			if (2 * length > ec) return false;
			// Chien search: positions where the locator's root sits.
			List<Integer> places = new ArrayList<>();
			for (int p = 0; p < n; p++) {
				int inverse = EXP[(255 - p) % 255];  // X^-1 for the power p from the end
				int v = 0;
				for (int i = length; i >= 0; i--) v = mul(v, inverse) ^ locator[i];
				if (v == 0) places.add(p);
			}
			if (places.size() != length) return false;
			// Forney: the evaluator, then each error's size.
			int[] evaluator = new int[ec];
			for (int i = 0; i < ec; i++) {
				int v = 0;
				for (int j = 0; j <= Math.min(i, length); j++) v ^= mul(locator[j], syndromes[i - j]);
				evaluator[i] = v;
			}
			for (int p : places) {
				int x = EXP[p], inverse = EXP[(255 - p) % 255];
				int top = 0;
				for (int i = ec - 1; i >= 0; i--) top = mul(top, inverse) ^ evaluator[i];
				int bottom = 0;
				for (int i = 1; i <= length; i += 2) {
					// The locator's derivative: odd terms only, one power down.
					int term = locator[i];
					for (int k = 0; k < i - 1; k++) term = mul(term, inverse);
					bottom ^= term;
				}
				if (bottom == 0) return false;
				int size = mul(x, div(top, bottom));
				word[n - 1 - p] ^= size;
			}
			return true;
		}
	}
}
