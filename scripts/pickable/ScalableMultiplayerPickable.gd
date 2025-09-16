@tool
class_name ScalableMultiplayerPickable
extends MultiplayerPickableObject

## XR Tools Scalable Pickable Object
##
## This script extends XRToolsPickable to support two-handed scaling.
## When grabbed with two hands, the object can be scaled by moving the hands
## closer together or further apart.

## Signal emitted when scaling starts
signal scaling_started(pickable)

## Signal emitted when scaling ends
signal scaling_ended(pickable)

## Signal emitted during scaling
signal scaling_updated(pickable, scale_factor)

## Minimum scale factor
@export var min_scale: float = 0.1

## Maximum scale factor
@export var max_scale: float = 10.0

## Scale smoothing factor (0.0 = instant, 1.0 = very smooth)
@export_range(0.0, 1.0) var scale_smoothing: float = 0.1

## Whether to center the object between hands while scaling
@export var center_while_scaling: bool = true

# Private scaling state
var _is_scaling: bool = false
var _initial_scale: Vector3
var _initial_hand_distance: float
var _target_scale: Vector3
var _scale_center_offset: Vector3

# Override the SecondHandGrab enum to add scaling
enum ScalableSecondHandGrab {
	IGNORE = 0, ## Ignore second grab
	SWAP = 1,   ## Swap to second hand
	SECOND = 2, ## Second hand grab
	SCALE = 3   ## Two-handed scaling
}

## Second hand grab mode for scalable objects
@export var scalable_second_hand_grab: ScalableSecondHandGrab = ScalableSecondHandGrab.SCALE

func _ready():
	super._ready()
	_target_scale = scale

# Override can_pick_up to handle scaling mode
func can_pick_up(by: Node3D) -> bool:
	# If we're using scalable second hand grab, convert it to the base enum
	if scalable_second_hand_grab == ScalableSecondHandGrab.SCALE:
		# Temporarily set to SECOND to allow the base class logic
		var original_mode = second_hand_grab
		second_hand_grab = SecondHandGrab.SECOND
		var result = super.can_pick_up(by)
		second_hand_grab = original_mode
		return result
	else:
		# Map scalable enum to base enum
		second_hand_grab = scalable_second_hand_grab as SecondHandGrab
		return super.can_pick_up(by)

# Override pick_up to handle scaling logic
func pick_up(by: Node3D) -> void:
	# Check if this should start scaling
	if (scalable_second_hand_grab == ScalableSecondHandGrab.SCALE and
	is_picked_up() and
	_grab_driver and _grab_driver.primary and
	by is XRToolsFunctionPickup and
	_grab_driver.primary.by is XRToolsFunctionPickup):

		_start_scaling(by)
		return

	# Handle regular pickup
	if scalable_second_hand_grab != ScalableSecondHandGrab.SCALE:
		second_hand_grab = scalable_second_hand_grab as SecondHandGrab
	else:
		second_hand_grab = SecondHandGrab.SECOND

	super.pick_up(by)

# Override let_go to handle scaling cleanup
func let_go(by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	# Check if we should stop scaling
	if _is_scaling:
		var primary_releasing = _grab_driver.primary and _grab_driver.primary.by == by
		var secondary_releasing = _grab_driver.secondary and _grab_driver.secondary.by == by

		if primary_releasing or secondary_releasing:
			_stop_scaling()

	super.let_go(by, p_linear_velocity, p_angular_velocity)

# Process scaling updates
func _physics_process(delta):
	super._physics_process(delta)

	if _is_scaling:
		_update_scaling(delta)

# Start two-handed scaling
func _start_scaling(second_grabber: Node3D):
	if _is_scaling:
		return

	print_verbose("%s> starting two-handed scaling" % name)
	_is_scaling = true
	_initial_scale = scale
	_target_scale = scale
	_initial_hand_distance = _get_hand_distance()

	# Calculate center offset for positioning
	if center_while_scaling:
		var center = _get_hands_center()
		_scale_center_offset = global_position - center

	# Temporarily set second hand grab to allow the grab
	var original_mode = second_hand_grab
	second_hand_grab = SecondHandGrab.SECOND

	# Call parent pickup to establish the second grab
	super.pick_up(second_grabber)

	# Restore our mode
	second_hand_grab = original_mode

	scaling_started.emit(self)

# Stop scaling mode
func _stop_scaling():
	if not _is_scaling:
		return

	print_verbose("%s> stopping two-handed scaling" % name)
	_is_scaling = false
	scaling_ended.emit(self)

# Update scaling based on hand distance
func _update_scaling(delta: float):
	if not _grab_driver or not _grab_driver.primary or not _grab_driver.secondary:
		_stop_scaling()
		return

	var current_distance = _get_hand_distance()
	if _initial_hand_distance <= 0:
		return

	# Calculate scale factor
	var distance_ratio = current_distance / _initial_hand_distance
	var new_scale = _initial_scale * distance_ratio

	# Clamp scale
	new_scale = new_scale.clamp(
		Vector3(min_scale, min_scale, min_scale),
		Vector3(max_scale, max_scale, max_scale)
	)

	_target_scale = new_scale

	# Apply smoothing
	if scale_smoothing > 0.0:
		scale = scale.lerp(_target_scale, 1.0 - pow(scale_smoothing, delta * 60.0))
	else:
		scale = _target_scale

	# Update position to keep object centered between hands
	if center_while_scaling:
		_update_center_position()

	scaling_updated.emit(self, distance_ratio)

# Get distance between the two grabbing hands
func _get_hand_distance() -> float:
	if not _grab_driver or not _grab_driver.primary or not _grab_driver.secondary:
		return 0.0

	var pos1 = _grab_driver.primary.by.global_position
	var pos2 = _grab_driver.secondary.by.global_position
	return pos1.distance_to(pos2)

# Get center point between hands
func _get_hands_center() -> Vector3:
	if not _grab_driver or not _grab_driver.primary or not _grab_driver.secondary:
		return global_position

	var pos1 = _grab_driver.primary.by.global_position
	var pos2 = _grab_driver.secondary.by.global_position
	return (pos1 + pos2) * 0.5

# Update object position to stay centered between hands
func _update_center_position():
	if not center_while_scaling:
		return

	var hands_center = _get_hands_center()
	var target_position = hands_center + _scale_center_offset

	# Apply the position through the grab driver
	if _grab_driver:
		_grab_driver.global_position = target_position

# Get current scale factor relative to initial scale
func get_scale_factor() -> float:
	if _initial_scale.x <= 0:
		return 1.0
	return scale.x / _initial_scale.x

# Check if currently being scaled
func is_scaling() -> bool:
	return _is_scaling
