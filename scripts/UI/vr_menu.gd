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

	# Configure the Viewport2DIn3D
	_viewport_2d.screen_size = screen_size
	_viewport_2d.viewport_size = viewport_size

	# Update grab collision to match screen size (slightly larger for easy grabbing)
	var grab_shape: CollisionShape3D = $GrabCollision
	if grab_shape and grab_shape.shape is BoxShape3D:
		var box = grab_shape.shape as BoxShape3D
		box.size = Vector3(screen_size.x + 0.1, screen_size.y + 0.1, 0.05)

	# Disable grab if not grabbable
	if not _grabbable:
		enabled = false  # XRToolsPickable.enabled — prevents pick_up

	# Add the Control to the viewport
	var viewport: SubViewport = _viewport_2d.get_node("Viewport")
	if viewport:
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(control)


## Play the open (grow) animation.
func open() -> void:
	scale = Vector3.ZERO
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3.ONE, 0.25) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)


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
	_tween.tween_property(self, "scale", Vector3.ZERO, 0.2) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_BACK)
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
	closed.emit()
	queue_free()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
