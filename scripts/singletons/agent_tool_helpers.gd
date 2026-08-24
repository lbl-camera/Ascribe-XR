## Pure, static validation for agent-forwarded tool calls. No side effects,
## no scene-tree access — easy to unit-test without a running game.
class_name AgentToolHelpers

const ROOM_NAMES := ["lab", "black", "passthrough", "world_scale"]
const DISPLAY_PARAMS := ["gamma", "opacity", "color_scalar", "max_steps", "step_size", "zoom"]


## Returns "" if `args` is a valid payload for the tool `name`, else a
## human-readable error message.
static func validate_tool(name: String, args: Dictionary) -> String:
	match name:
		"load_specimen":
			return _require_string(args, "specimen_id")
		"set_active_specimen":
			return _require_int(args, "index")
		"remove_specimen":
			return _require_int(args, "index")
		"set_room_scene":
			var err := _require_string(args, "name")
			if not err.is_empty():
				return err
			if not ROOM_NAMES.has(args["name"]):
				return "set_room_scene: 'name' must be one of %s, got '%s'" % [ROOM_NAMES, args["name"]]
			return ""
		"set_display_param":
			var idx_err := _require_int(args, "index")
			if not idx_err.is_empty():
				return idx_err
			var name_err := _require_string(args, "name")
			if not name_err.is_empty():
				return name_err
			if not DISPLAY_PARAMS.has(args["name"]):
				return "set_display_param: 'name' must be one of %s, got '%s'" % [DISPLAY_PARAMS, args["name"]]
			return _require_float(args, "value")
		"capture_viewport":
			return ""
		_:
			return "unknown tool '%s'" % name


static func _require_string(args: Dictionary, key: String) -> String:
	if not args.has(key):
		return "missing required key '%s'" % key
	if typeof(args[key]) != TYPE_STRING:
		return "'%s' must be a string" % key
	return ""


static func _require_int(args: Dictionary, key: String) -> String:
	if not args.has(key):
		return "missing required key '%s'" % key
	if typeof(args[key]) != TYPE_INT:
		return "'%s' must be an int" % key
	return ""


static func _require_float(args: Dictionary, key: String) -> String:
	if not args.has(key):
		return "missing required key '%s'" % key
	var t := typeof(args[key])
	if t != TYPE_FLOAT and t != TYPE_INT:
		return "'%s' must be a number" % key
	return ""
