class_name CalibrationLink
extends Node
## The connection to the phone that measures the screen for camera
## calibration. This device serves a small web page (calibration/phone.html)
## over HTTPS on the local network; the phone opens it by scanning a QR code
## with the address and a session code, and needs nothing installed. Browsers
## only let a page use the camera over HTTPS, so the game makes its own
## certificate once and keeps it in user://; the phone warns about it the
## first time.
##
## The phone posts each reading and is answered with the next patch to show
## (see CameraCalibration), so the screen and camera keep in step: the patch
## is drawn before the phone waits and looks.

signal phone_seen(info: Dictionary)  ## the phone opened the page and its camera
signal aimed(view: Dictionary)  ## while lining up, what the phone sees: {edge, ripple}

const PORTS := [8443, 8444, 8445, 8446, 8447]  # tried in turn, in case one is taken
const PAGE := "res://calibration/phone.html"
const METER := "res://calibration/meter.apk"  # the Shape Match Meter app (calibration/meter), which reads the camera's raw data
const METER_VERSION := 5  # its android:versionCode; an older meter is told to update
const KEY_PATH := "user://calibration_tls.key"
const CERT_PATH := "user://calibration_tls.crt"
const IDLE_LIMIT := 30.0  # seconds a quiet connection is kept open
const MAX_REQUEST := 65536  # bytes; anything bigger isn't from the page

## Called with a request's path and its JSON body; returns the JSON reply.
var handler: Callable
var token := ""
var port := 0

var _server := TCPServer.new()
var _tls: TLSOptions
var _peers: Array[Dictionary] = []  # {stream: StreamPeerTLS, buffer: PackedByteArray, idle: float}
var _page := ""


## Whether this build can serve the phone: a browser game can't listen.
static func supported() -> bool:
	return not OS.has_feature("web")


## Makes the certificate if there's none yet, which takes a few seconds on a
## phone, so it runs on a worker thread; then starts listening. Returns OK or
## the error.
func start() -> Error:
	_page = FileAccess.get_file_as_string(PAGE)
	if _page.is_empty():
		return ERR_FILE_NOT_FOUND
	var made := {}
	var task := WorkerThreadPool.add_task(func(): made.merge(_load_or_make_certificate()))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if not made.has("key"):
		return ERR_CANT_CREATE
	_tls = TLSOptions.server(made.key, made.cert)
	token = "%08x" % (randi() & 0x7fffffff)
	for p in PORTS:
		if _server.listen(p) == OK:
			port = p
			return OK
	return ERR_CANT_OPEN


func stop() -> void:
	for peer in _peers:
		peer.stream.disconnect_from_stream()
	_peers.clear()
	_server.stop()


func _exit_tree() -> void:
	stop()


static func _load_or_make_certificate() -> Dictionary:
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if FileAccess.file_exists(KEY_PATH) and FileAccess.file_exists(CERT_PATH) and key.load(KEY_PATH) == OK and cert.load(CERT_PATH) == OK:
		return {"key": key, "cert": cert}
	var crypto := Crypto.new()
	key = crypto.generate_rsa(2048)
	cert = crypto.generate_self_signed_certificate(key, "CN=Shape Match calibration,O=Shape Match,C=IL",
			"20260101000000", "20460101000000")
	key.save(KEY_PATH)
	cert.save(CERT_PATH)
	return {"key": key, "cert": cert}


## The addresses the phone may reach this device at, likeliest first: private
## IPv4 addresses on the local network.
static func local_addresses() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)
	var rank := func(a: String) -> int:
		if a.begins_with("192.168."):
			return 0
		if a.begins_with("10."):
			return 1
		var parts := a.split(".")
		if parts[0] == "172" and int(parts[1]) >= 16 and int(parts[1]) <= 31:
			return 2
		return 3
	found.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
	return found


func url(address: String) -> String:
	return "https://%s:%d/?s=%s" % [address, port, token]


func _process(delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var stream := StreamPeerTLS.new()
		if stream.accept_stream(_server.take_connection(), _tls) == OK:
			_peers.append({"stream": stream, "buffer": PackedByteArray(), "idle": 0.0})
	for peer in _peers.duplicate():
		var stream: StreamPeerTLS = peer.stream
		stream.poll()
		peer.idle += delta
		var status := stream.get_status()
		if status == StreamPeerTLS.STATUS_CONNECTED:
			var available := stream.get_available_bytes()
			if available > 0:
				var got := stream.get_partial_data(available)
				if got[0] == OK:
					peer.buffer.append_array(got[1])
					peer.idle = 0.0
				_answer(peer)
		if (status != StreamPeerTLS.STATUS_HANDSHAKING and status != StreamPeerTLS.STATUS_CONNECTED) \
				or peer.idle > IDLE_LIMIT or peer.buffer.size() > MAX_REQUEST:
			stream.disconnect_from_stream()
			_peers.erase(peer)


## Answers every whole request in peer's buffer.
func _answer(peer: Dictionary) -> void:
	while true:
		var text: String = peer.buffer.get_string_from_ascii()
		var head_end := text.find("\r\n\r\n")
		if head_end < 0:
			return
		var lines := text.substr(0, head_end).split("\r\n")
		var length := 0
		for line in lines:
			if line.to_lower().begins_with("content-length:"):
				length = int(line.substr(15).strip_edges())
		var body_start := head_end + 4
		if peer.buffer.size() < body_start + length:
			return  # the body is still coming
		var body: String = peer.buffer.slice(body_start, body_start + length).get_string_from_utf8()
		peer.buffer = peer.buffer.slice(body_start + length)
		var request := lines[0].split(" ")
		if request.size() < 2:
			_send(peer.stream, 400, "text/plain", "Bad request")
			continue
		var target := request[1]
		var path := target.get_slice("?", 0)
		var query := target.get_slice("?", 1) if target.contains("?") else ""
		if not ("s=" + token) in query.split("&"):
			_send(peer.stream, 403, "text/plain", "This calibration has ended. Scan the new code on the screen.")
			continue
		if path == "/":
			_send(peer.stream, 200, "text/html; charset=utf-8", _page)
			continue
		if path == "/meter.apk":
			_send(peer.stream, 200, "application/vnd.android.package-archive", FileAccess.get_file_as_bytes(METER),
					"Content-Disposition: attachment; filename=\"ShapeMatchMeter-%d.apk\"\r\n" % METER_VERSION)
			continue
		var json := JSON.new()
		var data = json.data if body and json.parse(body) == OK else {}
		if not data is Dictionary:
			data = {}
		if path == "/hello":
			phone_seen.emit(data)
			_send(peer.stream, 200, "application/json", JSON.stringify({"ok": true, "meter_version": METER_VERSION}))
		elif path == "/aim":
			aimed.emit(data)
			_send(peer.stream, 200, "application/json", JSON.stringify({"ok": true}))
		elif path == "/reading" and handler.is_valid():
			_send(peer.stream, 200, "application/json", JSON.stringify(handler.call(data)))
		else:
			_send(peer.stream, 404, "text/plain", "Not found")


## Sends a reply: body as text or bytes, with any extra header lines.
func _send(stream: StreamPeerTLS, code: int, type: String, body: Variant, extra := "") -> void:
	var bytes: PackedByteArray = body if body is PackedByteArray else str(body).to_utf8_buffer()
	var reason: String = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n%sConnection: keep-alive\r\n\r\n" \
			% [code, reason, type, bytes.size(), extra]
	stream.put_data(head.to_ascii_buffer() + bytes)
