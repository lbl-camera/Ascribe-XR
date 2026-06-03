@tool
class_name VRMenu
extends "res://addons/godot-xr-tools/objects/pickable.gd"

## VR Menu — A grabbable, animated 3D panel that renders a 2D Control.
##
## Spawned by MenuManager. Do not instantiate directly — use MenuManager.show_menu().
##
## Extends XRToolsPickable so it's natively recognized by the XR grab system.
## Grip button picks it up and moves it; trigger pointer interacts with the 2D UI.
##
## Structure:
##   VRMenu (XRToolsPickable / RigidBody3D)
##     ├── Viewport2DIn3D (XRToolsViewport2DIn3D) — renders Control, handles pointer
##     └── GrabCollision (CollisionShape3D) — grab collision (layer 3)

## Emitted when the menu is closed (after shrink animation completes).
signal closed

## Emitted when accept is triggered (caller connects as needed).
signal accepted

## The 2D Control being displayed.
var _content: Control = null

## Reference to the Viewport2DIn3D child.
@onready var _viewport_2d: XRToolsViewport2DIn3D = $Viewport2DIn3D

## Animation tween.
var _tween: Tween

## Whether the menu is currently closing.
var _is_closing: bool = false

## Whether grabbing is enabled for this menu.
var _grabbable: bool = true

## If true, the content Control is removed from the viewport before the menu
## is freed — keeping it alive for reuse (e.g., NetworkGateway).
var _preserve_content: bool = false


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	# Configure as a floating, non-physics object
	gravity_scale = 0.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	# XRToolsPickable config: hold to grab, restore frozen when released
	press_to_hold = true
	release_mode = ReleaseMode.FROZEN


## Configure the menu with a Control and options dictionary.
func setup(control: Control, options: Dictionary = {}) -> void:
	_content = control

	var screen_size: Vector2 = options.get("screen_size", Vector2(2.0, 1.2))
	var viewport_size: Vector2 = options.get("viewport_size", Vector2(1024, 614))
	_grabbable = options.get("grabbable", true)
	_preserve_content = options.get("preserve_content", false)

	# Configure the Viewport2DIn3D
	_viewport_2d.screen_size = screen_size
	_viewport_2d.viewport_size = viewport_size

	# Remove static-world layer (bit 1) from the pointer body so the
	# PlayerBody doesn't treat the menu as a wall and trigger fade-to-black.
	# Keep only bits 21 (pointable) and 23 (ui-objects).
	var pointer_body = _viewport_2d.get_node_or_null("StaticBody3D")
	if pointer_body:
		pointer_body.collision_layer = 0b0000_0000_0101_0000_0000_0000_0000_0000

	# Update grab collision to match screen size (slightly larger for easy grabbing).
	# Position it behind the viewport body so the pointer raycast hits the
	# viewport StaticBody3D first (enabling click-through to 2D UI).
	var grab_shape: CollisionShape3D = $GrabCollision
	if grab_shape and grab_shape.shape is BoxShape3D:
		var box = grab_shape.shape as BoxShape3D
		box.size = Vector3(screen_size.x + 0.1, screen_size.y + 0.1, 0.05)
		grab_shape.position.z = -0.04

	# Disable grab if not grabbable
	if not _grabbable:
		enabled = false  # XRToolsPickable.enabled — prevents pick_up

	# Add the Control to the viewport and wire up the Viewport2DIn3D render
	# pipeline. Normally Viewport2DIn3D expects a PackedScene set via its
	# `scene` property. Since we inject an already-instantiated Control, we
	# need to manually:
	#  1. Add the control to the SubViewport
	#  2. Tell Viewport2DIn3D about the scene_node
	#  3. Force a full render refresh so material + albedo texture are wired
	var viewport: SubViewport = _viewport_2d.get_node("Viewport")
	if viewport:
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(control)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

		# Let Viewport2DIn3D know this is the active scene content
		_viewport_2d.scene_node = control

		# Force render update to wire albedo texture onto the screen mesh.
		# Exclude _DIRTY_SCENE — we manually injected the control above;
		# the scene handler would remove and destroy it.
		_viewport_2d._dirty = _viewport_2d._DIRTY_ALL & ~_viewport_2d._DIRTY_SCENE
		_viewport_2d._update_render()


## Play the open (grow) animation.
func open() -> void:
	scale = Vector3(0.01, 0.01, 0.01)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3.ONE, 0.3) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


## Play the close (shrink) animation, then free.
func close() -> void:
	if _is_closing:
		return
	_is_closing = true

	# Drop if held
	if is_picked_up():
		drop()

	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.2) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(_on_close_complete)


## Immediately close without animation (used when replacing menus).
func close_immediate() -> void:
	if _is_closing:
		return
	_is_closing = true

	# Drop if held
	if is_picked_up():
		drop()

	_kill_tween()
	_on_close_complete()


## Emit accept signal (call from the displayed Control or externally).
func accept() -> void:
	accepted.emit()


func _on_close_complete() -> void:
	# Preserve content if requested — remove it from the viewport before
	# queue_free destroys the entire VRMenu tree.
	if _preserve_content and _content and is_instance_valid(_content):
		var viewport: SubViewport = _viewport_2d.get_node_or_null("Viewport")
		if viewport and _content.get_parent() == viewport:
			viewport.remove_child(_content)
	closed.emit()
	queue_free()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
