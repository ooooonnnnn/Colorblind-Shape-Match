class_name QrCode
extends Control
## A QR code, drawn black on white with its quiet zone, for a phone's camera
## to scan: the calibration page shows the address the phone opens with it.
## Encodes text as bytes at error correction level M, in the smallest of
## versions 1 to 9 it fits (up to 180 bytes), after the QR code standard
## (ISO/IEC 18004) and Nayuki's reference encoder.

const QUIET := 4  # modules of white around the code, as the standard asks
## Per version 1-9 at level M: error correction codewords per block, and the
## blocks as [count, data codewords] groups.
const BLOCKS := [
	[10, [[1, 16]]], [16, [[1, 28]]], [26, [[1, 44]]], [18, [[2, 32]]], [24, [[2, 43]]],
	[16, [[4, 27]]], [18, [[4, 31]]], [22, [[2, 38], [2, 39]]], [22, [[3, 36], [2, 37]]],
]
const ALIGNMENT := [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46]]
const LEVEL_M := 0  # its two format bits

var text := "":
	set(v):
		text = v
		_modules = encode(text)
		queue_redraw()

var _modules: Array[PackedByteArray] = []  # rows of 1 dark, 0 light


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	if _modules.is_empty():
		return
	var count := _modules.size() + QUIET * 2
	var module := floorf(minf(size.x, size.y) / count)  # whole pixels keep the edges crisp
	var origin := ((size - Vector2.ONE * module * count) / 2).floor() + Vector2.ONE * module * QUIET
	for y in _modules.size():
		for x in _modules.size():
			if _modules[y][x]:
				draw_rect(Rect2(origin + Vector2(x, y) * module, Vector2.ONE * module), Color.BLACK)


## The modules of text's QR code, or none if it is too long.
static func encode(value: String) -> Array[PackedByteArray]:
	var bytes := value.to_utf8_buffer()
	var version := 0
	for v in range(1, BLOCKS.size() + 1):
		if 4 + 8 + bytes.size() * 8 <= _data_codewords(v) * 8:
			version = v
			break
	if version == 0:
		push_error("Too long for a QR code: %s" % value)
		return []
	var code := _Grid.new(version)
	code.draw_function_patterns()
	code.draw_codewords(_with_error_correction(version, _data(version, bytes)))
	var best: Array[PackedByteArray] = []
	var lowest := INF
	for mask in 8:
		var trial := code.copy()
		trial.apply_mask(mask)
		trial.draw_format(mask)
		var penalty := trial.penalty()
		if penalty < lowest:
			lowest = penalty
			best = trial.modules
	return best


static func _data_codewords(version: int) -> int:
	var total := 0
	for group in BLOCKS[version - 1][1]:
		total += group[0] * group[1]
	return total


## Byte mode, its length, the bytes, then the terminator and padding.
static func _data(version: int, bytes: PackedByteArray) -> PackedByteArray:
	var bits: Array[int] = []
	var put := func(value: int, length: int):
		for i in range(length - 1, -1, -1):
			bits.append((value >> i) & 1)
	put.call(0b0100, 4)
	put.call(bytes.size(), 8)
	for b in bytes:
		put.call(b, 8)
	var capacity := _data_codewords(version) * 8
	put.call(0, mini(4, capacity - bits.size()))
	while bits.size() % 8:
		bits.append(0)
	var out := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var b := 0
		for j in 8:
			b = (b << 1) | bits[i + j]
		out.append(b)
	var pad := 0xEC
	while out.size() < capacity / 8:
		out.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	return out


## The data split into blocks, each with its Reed-Solomon codewords, then
## interleaved: every block's first codeword, every block's second, ...
static func _with_error_correction(version: int, data: PackedByteArray) -> PackedByteArray:
	var ec_count: int = BLOCKS[version - 1][0]
	var divisor := _rs_divisor(ec_count)
	var blocks: Array[PackedByteArray] = []
	var ecs: Array[PackedByteArray] = []
	var at := 0
	for group in BLOCKS[version - 1][1]:
		for i in group[0]:
			var block := data.slice(at, at + group[1])
			at += group[1]
			blocks.append(block)
			ecs.append(_rs_remainder(block, divisor))
	var out := PackedByteArray()
	var longest := blocks[-1].size()
	for i in longest:
		for block in blocks:
			if i < block.size():
				out.append(block[i])
	for i in ec_count:
		for ec in ecs:
			out.append(ec[i])
	return out


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_multiply(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_multiply(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor := b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in result.size():
			result[i] ^= _gf_multiply(divisor[i], factor)
	return result


## Multiplication in GF(2^8) modulo x^8 + x^4 + x^3 + x^2 + 1.
static func _gf_multiply(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


## The square of modules being built, and which of them are fixed patterns.
class _Grid:
	var version := 1
	var size := 21
	var modules: Array[PackedByteArray] = []
	var fixed: Array[PackedByteArray] = []

	func _init(v: int) -> void:
		version = v
		size = v * 4 + 17
		for y in size:
			var row := PackedByteArray()
			row.resize(size)
			modules.append(row)
			fixed.append(row.duplicate())

	func copy() -> _Grid:
		var other := _Grid.new(version)
		for y in size:
			other.modules[y] = modules[y].duplicate()
			other.fixed[y] = fixed[y].duplicate()
		return other

	func set_fixed(x: int, y: int, dark: bool) -> void:
		modules[y][x] = 1 if dark else 0
		fixed[y][x] = 1

	func draw_function_patterns() -> void:
		for i in size:
			set_fixed(6, i, i % 2 == 0)
			set_fixed(i, 6, i % 2 == 0)
		for corner in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var x: int = corner.x + dx
					var y: int = corner.y + dy
					if x >= 0 and x < size and y >= 0 and y < size:
						var distance := maxi(absi(dx), absi(dy))
						set_fixed(x, y, distance != 2 and distance != 4)
		var places: Array = ALIGNMENT[version - 1]
		var last := places.size() - 1
		for i in places.size():
			for j in places.size():
				if (i == 0 and j == 0) or (i == 0 and j == last) or (i == last and j == 0):
					continue  # where the finders are
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						set_fixed(places[i] + dx, places[j] + dy, maxi(absi(dx), absi(dy)) != 1)
		draw_format(0)  # reserves the format areas; the real mask is drawn later
		if version >= 7:
			var rem := version
			for i in 12:
				rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
			var bits := version << 12 | rem
			for i in 18:
				var dark := (bits >> i) & 1 == 1
				set_fixed(size - 11 + i % 3, i / 3, dark)
				set_fixed(i / 3, size - 11 + i % 3, dark)

	func draw_format(mask: int) -> void:
		var data := LEVEL_M << 3 | mask
		var rem := data
		for i in 10:
			rem = (rem << 1) ^ ((rem >> 9) * 0x537)
		var bits := (data << 10 | rem) ^ 0x5412
		var bit := func(i: int) -> bool: return (bits >> i) & 1 == 1
		for i in 6:
			set_fixed(8, i, bit.call(i))
		set_fixed(8, 7, bit.call(6))
		set_fixed(8, 8, bit.call(7))
		set_fixed(7, 8, bit.call(8))
		for i in range(9, 15):
			set_fixed(14 - i, 8, bit.call(i))
		for i in 8:
			set_fixed(size - 1 - i, 8, bit.call(i))
		for i in range(8, 15):
			set_fixed(8, size - 15 + i, bit.call(i))
		set_fixed(8, size - 8, true)  # always dark

	## Lays the codewords' bits in the standard's zigzag: two columns at a
	## time from the right, up then down, around the fixed patterns.
	func draw_codewords(data: PackedByteArray) -> void:
		var i := 0
		var right := size - 1
		while right >= 1:
			if right == 6:
				right = 5  # the vertical timing pattern
			for vert in size:
				for j in 2:
					var x := right - j
					var upward := ((right + 1) & 2) == 0
					var y := size - 1 - vert if upward else vert
					if not fixed[y][x] and i < data.size() * 8:
						modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1
						i += 1
			right -= 2

	func apply_mask(mask: int) -> void:
		for y in size:
			for x in size:
				if fixed[y][x]:
					continue
				var flip := false
				match mask:
					0: flip = (x + y) % 2 == 0
					1: flip = y % 2 == 0
					2: flip = x % 3 == 0
					3: flip = (x + y) % 3 == 0
					4: flip = (x / 3 + y / 2) % 2 == 0
					5: flip = x * y % 2 + x * y % 3 == 0
					6: flip = (x * y % 2 + x * y % 3) % 2 == 0
					7: flip = ((x + y) % 2 + x * y % 3) % 2 == 0
				if flip:
					modules[y][x] ^= 1

	## The standard's penalty for runs, blocks and dark/light balance (its
	## finder-lookalike rule is left out); the mask scoring least is used.
	func penalty() -> float:
		var score := 0
		for line in 2:
			for a in size:
				var run := 1
				for b in range(1, size):
					var here: int = modules[a][b] if line == 0 else modules[b][a]
					var before: int = modules[a][b - 1] if line == 0 else modules[b - 1][a]
					if here == before:
						run += 1
						if run == 5:
							score += 3
						elif run > 5:
							score += 1
					else:
						run = 1
		var dark := 0
		for y in size:
			for x in size:
				dark += modules[y][x]
				if x < size - 1 and y < size - 1:
					var c := modules[y][x]
					if c == modules[y][x + 1] and c == modules[y + 1][x] and c == modules[y + 1][x + 1]:
						score += 3
		var total := size * size
		score += ((absi(dark * 20 - total * 10) + total - 1) / total - 1) * 10
		return score
