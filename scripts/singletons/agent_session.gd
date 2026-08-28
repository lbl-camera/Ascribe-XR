## AgentSession -- WebSocket client for the persistent per-room conversational
## agent (ascribe-link /ws/agent/{room_id}). Thin plumbing: all frame
## build/parse logic lives in AgentSessionHelpers so it can be unit tested
## without a scene tree.
extends Node

signal connected
signal disconnected
signal agent_text(text: String)
signal agent_text_done
signal status_changed(text: String)
signal tool_call_received(request_id: String, name: String, args: Dictionary, executor: int)
signal history_received(client_id: int, entries: Array)
signal error_received(message: String)
signal turn_queued(position: int)
signal tts_audio(header: Dictionary, payload: PackedByteArray)
signal speaker_bound(client_id: int)
signal speaker_released
signal transcript_received(text: String, client_id: int)
signal agent_audio_ended(interrupted: bool)

const RECONNECT_BASE_SEC := 1.0
const RECONNECT_MAX_SEC := 8.0

var client_id: int = -1

var _socket: WebSocketPeer = null
var _room_id: String = ""
var _explicit_close: bool = false
var _was_connected: bool = false
var _reconnect_delay: float = RECONNECT_BASE_SEC
var _reconnect_timer: float = 0.0
var _reconnecting: bool = false


func connect_to_room(room_id: String = Config.webrtcroomname) -> void:
	_room_id = room_id
	_explicit_close = false
	_reconnecting = false
	_reconnect_delay = RECONNECT_BASE_SEC
	_open_socket()


func close() -> void:
	_explicit_close = true
	_reconnecting = false
	if _socket != null:
		_socket.close()
	_socket = null


func send_text(text: String) -> void:
	_send_text_frame(AgentSessionHelpers.build_text_frame(text))


func send_tool_result(request_id: String, result) -> void:
	_send_text_frame(AgentSessionHelpers.build_tool_result_frame(request_id, result))


func send_interrupt() -> void:
	_send_text_frame(AgentSessionHelpers.build_interrupt_frame())


func send_end_conversation() -> void:
	_send_text_frame(AgentSessionHelpers.build_end_conversation_frame())


func send_screenshot(jpeg: PackedByteArray) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := AgentSessionHelpers.encode_binary({"kind": "screenshot", "mime": "image/jpeg"}, jpeg)
	_socket.send(frame, WebSocketPeer.WRITE_MODE_BINARY)


func send_bind() -> void:
	_send_text_frame(AgentSessionHelpers.build_bind_frame())


func send_unbind() -> void:
	_send_text_frame(AgentSessionHelpers.build_unbind_frame())


func send_audio(pcm16: PackedByteArray, rate: int) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := AgentSessionHelpers.encode_binary(AgentSessionHelpers.audio_header(rate), pcm16)
	_socket.send(frame, WebSocketPeer.WRITE_MODE_BINARY)


func _open_socket() -> void:
	_socket = WebSocketPeer.new()
	var url := "%s/%s" % [Config.agent_ws_url, _room_id]
	_socket.connect_to_url(url)


func _send_text_frame(json_text: String) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(json_text)


func _process(delta: float) -> void:
	if _explicit_close:
		return

	if _reconnecting:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_reconnecting = false
			_open_socket()
		return

	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _was_connected:
			_was_connected = true
			_reconnect_delay = RECONNECT_BASE_SEC
			connected.emit()
		while _socket.get_available_packet_count() > 0:
			_receive_packet()
	elif state == WebSocketPeer.STATE_CLOSED:
		if _was_connected:
			_was_connected = false
			disconnected.emit()
		_socket = null
		if not _explicit_close:
			_begin_reconnect()


func _begin_reconnect() -> void:
	_reconnecting = true
	_reconnect_timer = _reconnect_delay
	_reconnect_delay = min(_reconnect_delay * 2.0, RECONNECT_MAX_SEC)


func _receive_packet() -> void:
	# ORDER MATTERS: was_string_packet() reports on the packet most recently
	# retrieved with get_packet(). Calling it first classifies THIS packet by
	# the PREVIOUS packet's type -- which silently misrouted the first frame
	# of every connection (the history/client_id handshake) into the binary
	# parser and broke every text<->binary boundary in the TTS stream.
	var packet := _socket.get_packet()
	var was_string := _socket.was_string_packet()
	if was_string:
		var json_text := packet.get_string_from_utf8()
		_dispatch_frame(AgentSessionHelpers.parse_server_frame(json_text))
	else:
		_dispatch_binary_frame(AgentSessionHelpers.decode_binary(packet))


## Coerce a frame field to int, tolerating an explicit JSON null (the server
## can legitimately send `client_id: null` -- e.g. a transcript finalized for a
## speaker that already disconnected). `int(null)` is a runtime error in GDScript.
static func _int_or(frame: Dictionary, key: String, fallback: int) -> int:
	var raw: Variant = frame.get(key, fallback)
	if raw == null:
		return fallback
	return int(raw)


func _dispatch_frame(frame: Dictionary) -> void:
	if frame.has("error"):
		error_received.emit(str(frame["error"]))
		return

	match frame.get("type"):
		"agent_text":
			agent_text.emit(str(frame.get("text", "")))
		"agent_text_done":
			agent_text_done.emit()
		"tool_call":
			tool_call_received.emit(
				str(frame.get("request_id", "")),
				str(frame.get("name", "")),
				frame.get("args", {}),
				_int_or(frame, "executor", -1)
			)
		"status":
			status_changed.emit(str(frame.get("text", "")))
		"error":
			error_received.emit(str(frame.get("message", "")))
		"history":
			client_id = _int_or(frame, "client_id", -1)
			history_received.emit(client_id, frame.get("entries", []))
		"turn_queued":
			turn_queued.emit(_int_or(frame, "position", 0))
		"speaker_bound":
			speaker_bound.emit(_int_or(frame, "client_id", -1))
		"speaker_released":
			speaker_released.emit()
		"transcript":
			transcript_received.emit(str(frame.get("text", "")), _int_or(frame, "client_id", -1))
		"agent_audio_end":
			# Null-safe default: an older/odd server payload without the flag
			# is treated as a normal (non-interrupted) end.
			agent_audio_ended.emit(bool(frame.get("interrupted", false)))
		_:
			# Unknown/reserved type: client-side leniency, server-side strictness.
			error_received.emit("unknown frame type '%s'" % str(frame.get("type")))


func _dispatch_binary_frame(decoded: Dictionary) -> void:
	if decoded.has("error"):
		error_received.emit(str(decoded["error"]))
		return
	var header: Dictionary = decoded["header"]
	var payload: PackedByteArray = decoded["payload"]
	match header.get("kind"):
		"tts":
			tts_audio.emit(header, payload)
		_:
			push_warning("agent binary frame: unknown kind '%s'" % str(header.get("kind")))
