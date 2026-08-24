## AgentToolDispatcher -- thin wiring between AgentSession.tool_call_received
## and SceneManager's RPCs. All validation logic lives in the pure, testable
## AgentToolHelpers; this autoload only maps a validated tool call onto the
## corresponding SceneManager call and replies over AgentSession.
extends Node

## Emitted when a tool call arrives whose executor is a different peer than
## this client — nothing is executed locally; callers may append a transcript
## notice.
signal tool_executed_remotely(name: String)


func _ready() -> void:
	AgentSession.tool_call_received.connect(_on_tool_call_received)


func _on_tool_call_received(request_id: String, name: String, args: Dictionary, executor: int) -> void:
	if AgentSession.client_id != executor:
		tool_executed_remotely.emit(name)
		return

	var err := AgentToolHelpers.validate_tool(name, args)
	if not err.is_empty():
		AgentSession.send_tool_result(request_id, {"error": err})
		return

	var result := _execute_tool(name, args)
	AgentSession.send_tool_result(request_id, result)


func _execute_tool(name: String, args: Dictionary) -> Dictionary:
	match name:
		"load_specimen":
			SceneManager.specimen_job_done.rpc(args["specimen_id"], "agent_chat", Config.webrtcroomname, "")
			return {"ok": true}
		"set_active_specimen":
			SceneManager.set_active_specimen.rpc(args["index"])
			return {"ok": true}
		"remove_specimen":
			SceneManager.remove_specimen.rpc(args["index"])
			return {"ok": true}
		"set_room_scene":
			SceneManager.set_room_scene_rpc.rpc(args["name"])
			return {"ok": true}
		"set_display_param":
			SceneManager.set_display_param.rpc(args["index"], args["name"], args["value"])
			return {"ok": true}
		"capture_viewport":
			return {"error": "not implemented"}
		_:
			return {"error": "unknown tool '%s'" % name}
