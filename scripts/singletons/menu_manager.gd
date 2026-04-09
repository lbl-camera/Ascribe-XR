extends Node

## MenuManager — Global singleton for spawning VR menus.
##
## Supports multiple concurrent menus via named slots:
##   MenuManager.show_menu(my_control)                          # uses "default" slot
##   MenuManager.show_menu(my_control, { "slot": "specimen" })  # named slot
##   MenuManager.close_menu("specimen")
##   MenuManager.close_all_menus()

## Emitted when a menu is opened. Passes the VRMenu instance and slot name.
signal menu_opened(vr_menu: Node3D, slot: String)

## Emitted when a menu is closed. Passes the VRMenu instance and slot name.
signal menu_closed(vr_menu: Node3D, slot: String)

## Active menus keyed by slot name.
var _active_menus: Dictionary = {}

## Preloaded VR menu scene.
var _vr_menu_scene: PackedScene = preload("res://scenes/UI/vr_menu.tscn")


## Show a menu in front of the user.
##
## [param control] - An already-instantiated Control node to display.
## [param options] - Optional dictionary:
##   "slot":            String  — named slot (default "default"); re-using a slot closes the previous menu in it
##   "screen_size":     Vector2 — physical size in meters (default 2.0 x 1.2)
##   "viewport_size":   Vector2 — render resolution in pixels (default 1024 x 614)
##   "distance":        float   — meters from user's head (default 1.5)
##   "grabbable":       bool    — whether the menu can be grabbed (default true)
##   "preserve_content": bool   — if true, the Control is removed from the viewport before the menu is freed (default false)
##   "on_close":        Callable — called when the menu is dismissed
##   "on_accept":       Callable — forwarded to the VRMenu; caller wires as needed
func show_menu(control: Control, options: Dictionary = {}) -> Node3D:
	var slot: String = options.get("slot", "default")

	# Close any existing menu in this slot immediately
	var existing = _active_menus.get(slot)
	if existing and is_instance_valid(existing):
		existing.close_immediate()
		_active_menus.erase(slot)

	# Instantiate the VR menu
	var vr_menu = _vr_menu_scene.instantiate()

	# Add to scene tree first so _ready fires and nodes resolve
	var root = get_tree().root.get_child(0)  # Main scene
	root.add_child(vr_menu)

	# Configure
	vr_menu.setup(control, options)

	# Position in front of the user, with optional lateral offset
	var offset: Vector2 = options.get("offset", Vector2.ZERO)
	_position_in_front_of_user(vr_menu, options.get("distance", 1.5), offset)

	# Connect close signal
	vr_menu.closed.connect(_on_menu_closed.bind(vr_menu, slot))

	# Wire optional callbacks
	var on_close = options.get("on_close", Callable())
	if on_close.is_valid():
		vr_menu.closed.connect(on_close)

	var on_accept = options.get("on_accept", Callable())
	if on_accept.is_valid():
		vr_menu.accepted.connect(on_accept)

	_active_menus[slot] = vr_menu

	# Play the open animation
	vr_menu.open()

	menu_opened.emit(vr_menu, slot)
	return vr_menu


## Close a menu in the given slot (with animation).
func close_menu(slot: String = "default") -> void:
	var vr_menu = _active_menus.get(slot)
	if vr_menu and is_instance_valid(vr_menu):
		vr_menu.close()


## Close all active menus.
func close_all_menus() -> void:
	for slot in _active_menus.keys():
		var vr_menu = _active_menus[slot]
		if vr_menu and is_instance_valid(vr_menu):
			vr_menu.close()


## Returns true if a menu is showing in the given slot.
func has_active_menu(slot: String = "default") -> bool:
	var vr_menu = _active_menus.get(slot)
	return vr_menu != null and is_instance_valid(vr_menu)


## Position a node in front of the XR camera at eye level, facing the user.
## [param offset] — lateral (x) and vertical (y) offset in camera-relative space.
##   Positive x = right, positive y = up.
func _position_in_front_of_user(node: Node3D, distance: float, offset: Vector2 = Vector2.ZERO) -> void:
	var camera := _get_xr_camera()
	if not camera:
		# Fallback: use MenuSpawnMarker if available
		var marker = get_tree().root.get_node_or_null("Main/MenuSpawnMarker")
		if marker:
			node.global_position = marker.global_position + Vector3(offset.x, offset.y, 0)
			node.look_at(node.global_position + Vector3.FORWARD, Vector3.UP)
		else:
			push_warning("MenuManager: No XRCamera3D or MenuSpawnMarker found")
		return

	# Get camera forward direction (negative Z in camera space), projected onto XZ plane
	var forward = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	# Right vector (perpendicular to forward on XZ plane)
	var right = forward.cross(Vector3.UP).normalized()

	# Spawn position: in front of camera at eye level, with lateral/vertical offset
	var spawn_pos = camera.global_position + forward * distance
	spawn_pos += right * offset.x
	spawn_pos.y = camera.global_position.y + offset.y

	node.global_position = spawn_pos

	# Face the menu toward the user (+Z faces camera)
	var away = spawn_pos + forward
	node.look_at(away, Vector3.UP)


## Find the XRCamera3D in the scene tree.
func _get_xr_camera() -> XRCamera3D:
	# Try the known path first (XROrigin3D/XRCamera3D)
	var root = get_tree().root.get_child(0)
	if root:
		var camera = root.get_node_or_null("XROrigin3D/XRCamera3D")
		if camera is XRCamera3D:
			return camera

	# Fallback: search the tree
	return _find_node_by_class(get_tree().root, "XRCamera3D") as XRCamera3D


## Recursive helper to find a node by class name.
func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str or node is XRCamera3D:
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


## Handle menu closed signal.
func _on_menu_closed(vr_menu: Node3D, slot: String) -> void:
	if _active_menus.get(slot) == vr_menu:
		_active_menus.erase(slot)
	menu_closed.emit(vr_menu, slot)
