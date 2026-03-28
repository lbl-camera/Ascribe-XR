extends Node

## MenuManager — Global singleton for spawning VR menus.
##
## Usage:
##   MenuManager.show_menu(my_control)
##   MenuManager.show_menu(my_control, { "screen_size": Vector2(2.0, 1.2) })
##   MenuManager.close_menu()

## Emitted when a menu is opened. Passes the VRMenu instance.
signal menu_opened(vr_menu: Node3D)

## Emitted when a menu is closed. Passes the VRMenu instance.
signal menu_closed(vr_menu: Node3D)

## The currently active VR menu (null if none).
var active_menu: Node3D = null

## Preloaded VR menu scene.
var _vr_menu_scene: PackedScene = preload("res://scenes/UI/vr_menu.tscn")


## Show a menu in front of the user.
##
## [param control] - An already-instantiated Control node to display.
## [param options] - Optional dictionary:
##   "screen_size":    Vector2 — physical size in meters (default 2.0 x 1.2)
##   "viewport_size":  Vector2 — render resolution in pixels (default 1024 x 614)
##   "distance":       float   — meters from user's head (default 1.5)
##   "grabbable":      bool    — whether the menu can be grabbed (default true)
##   "on_close":       Callable — called when the menu is dismissed
##   "on_accept":      Callable — forwarded to the VRMenu; caller wires as needed
func show_menu(control: Control, options: Dictionary = {}) -> Node3D:
	# Close any existing menu immediately
	if active_menu and is_instance_valid(active_menu):
		active_menu.close_immediate()

	# Instantiate the VR menu
	var vr_menu = _vr_menu_scene.instantiate()

	# Add to scene tree first so _ready fires and nodes resolve
	var root = get_tree().root.get_child(0)  # Main scene
	root.add_child(vr_menu)

	# Configure
	vr_menu.setup(control, options)

	# Position in front of the user
	_position_in_front_of_user(vr_menu, options.get("distance", 1.5))

	# Connect close signal
	vr_menu.closed.connect(_on_menu_closed.bind(vr_menu))

	# Wire optional callbacks
	var on_close = options.get("on_close", Callable())
	if on_close.is_valid():
		vr_menu.closed.connect(on_close)

	var on_accept = options.get("on_accept", Callable())
	if on_accept.is_valid():
		vr_menu.accepted.connect(on_accept)

	active_menu = vr_menu

	# Play the open animation
	vr_menu.open()

	menu_opened.emit(vr_menu)
	return vr_menu


## Close the currently active menu (with animation).
func close_menu() -> void:
	if active_menu and is_instance_valid(active_menu):
		active_menu.close()


## Returns true if a menu is currently showing.
func has_active_menu() -> bool:
	return active_menu != null and is_instance_valid(active_menu)


## Position a node in front of the XR camera at eye level, facing the user.
func _position_in_front_of_user(node: Node3D, distance: float) -> void:
	var camera := _get_xr_camera()
	if not camera:
		push_warning("MenuManager: XRCamera3D not found, placing menu at origin")
		return

	# Get camera forward direction (negative Z in camera space), projected onto XZ plane
	var forward = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		# Camera looking straight up/down — fall back to global forward
		forward = Vector3.FORWARD
	forward = forward.normalized()

	# Spawn position: in front of camera at eye level
	var spawn_pos = camera.global_position + forward * distance
	# Keep at eye height
	spawn_pos.y = camera.global_position.y

	node.global_position = spawn_pos

	# Face the menu toward the user
	node.look_at(camera.global_position, Vector3.UP)


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
func _on_menu_closed(vr_menu: Node3D) -> void:
	if active_menu == vr_menu:
		active_menu = null
	menu_closed.emit(vr_menu)
