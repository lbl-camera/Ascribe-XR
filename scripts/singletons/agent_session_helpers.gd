## Pure helpers for the agent conversation WebSocket wire protocol.
##
## Mirrors ascribe_link/agent_ws/protocol.py. TEXT frames are JSON objects
## with a required "type" key. BINARY frames are:
##     <4-byte little-endian uint32: header_len>
##     <header_len bytes: UTF-8 JSON header>
##     <raw bytes: payload>
##
## No scene-tree dependencies -- safe to unit test with gdUnit4.
class_name AgentSessionHelpers
extends RefCounted


## Build a client->server "text" frame.
static func build_text_frame(text: String) -> String:
	return JSON.stringify({"type": "text", "text": text})


## Build a client->server "tool_result" frame.
static func build_tool_result_frame(request_id: String, result) -> String:
	return JSON.stringify({"type": "tool_result", "request_id": request_id, "result": result})


## Build a client->server "interrupt" frame.
static func build_interrupt_frame() -> String:
	return JSON.stringify({"type": "interrupt"})


## Build a client->server "end_conversation" frame.
static func build_end_conversation_frame() -> String:
	return JSON.stringify({"type": "end_conversation"})


## Parse a server->client TEXT frame.
##
## Returns the decoded Dictionary on success (untyped pass-through -- typed
## dispatch happens in AgentSession), or {"error": String} on bad JSON or a
## missing/invalid "type" key.
static func parse_server_frame(json_text: String) -> Dictionary:
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		return {"error": "agent frame: invalid JSON"}
	if not parsed.has("type") or not (parsed["type"] is String):
		return {"error": "agent frame: missing 'type'"}
	# Godot's JSON.parse_string() returns ALL numbers as float, regardless of
	# whether the source JSON was an integer literal. Coerce known integer
	# fields back to int so callers get the typing the wire protocol implies.
	for key in ["client_id", "position", "executor"]:
		if parsed.has(key):
			parsed[key] = int(parsed[key])
	return parsed


## Encode a BINARY frame: <u32 LE header_len><UTF-8 JSON header><raw payload>.
static func encode_binary(header: Dictionary, payload: PackedByteArray) -> PackedByteArray:
	var header_bytes := JSON.stringify(header).to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, header_bytes.size())
	out.append_array(header_bytes)
	out.append_array(payload)
	return out
