@tool
class_name ScalableMultiplayerPickable
extends MultiplayerPickable

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

## Whether to scale mass with volume (scale^3)
@export var scale_mass_with_volume: bool = true

# Override the SecondHandGrab enum to add scaling
enum ScalableSecondHandGrab {
	IGNORE = 0, ## Ignore second grab
	SWAP = 1,   ## Swap to second hand
	SECOND = 2, ## Second hand grab
	SCALE = 3   ## Two-handed scaling
}

## Second hand grab mode for scalable objects
@export var scalable_second_hand_grab: ScalableSecondHandGrab = ScalableSecondHandGrab.SCALE

# Private scaling state
var _is_scaling: bool = false
var _initial_scale_factor: float = 1.0
var _current_scale_factor: float = 1.0
var _target_scale_factor: float = 1.0
var _initial_hand_distance: float
var _scale_center_offset: Vector3
var _original_mass: float

# Store references to scalable components
var _collision_shapes: Array[CollisionShape3D] = []
var _mesh_instances: Array[Node] = []
var _original_collision_data: Array[Dictionary] = []
var _original_mesh_data: Array[Dictionary] = []

func _ready():
	super._ready()
	_original_mass = mass
	_cache_scalable_components()

# Cache all collision shapes and mesh instances for scaling
func _cache_scalable_components():
	_collision_shapes.clear()
	_mesh_instances.clear()
	_original_collision_data.clear()
	_original_mesh_data.clear()

	_find_scalable_components(self)

	print_verbose("%s> cached %d collision shapes and %d mesh instances" %
		[name, _collision_shapes.size(), _mesh_instances.size()])

# Recursively find collision shapes and mesh instances
func _find_scalable_components(node: Node):
	if node is CollisionShape3D:
		var collision_shape = node as CollisionShape3D
		_collision_shapes.append(collision_shape)
		_original_collision_data.append({
			"shape": collision_shape.shape,
			"original_scale": _get_shape_scale(collision_shape.shape)
		})

	elif node is MeshInstance3D or node is VolumeLayers:
		_mesh_instances.append(node)
		_original_mesh_data.append({
			"original_scale": node.scale
		})

	# Recursively check children
	for child in node.get_children():
		_find_scalable_components(child)

# Get the effective scale of a collision shape
func _get_shape_scale(shape: Shape3D) -> Vector3:
	if not shape:
		return Vector3.ONE

	# Different shapes store scale differently
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size
	elif shape is SphereShape3D:
		var radius = (shape as SphereShape3D).radius
		return Vector3(radius, radius, radius) * 2.0
	elif shape is CylinderShape3D:
		var cyl = shape as CylinderShape3D
		return Vector3(cyl.radius * 2.0, cyl.height, cyl.radius * 2.0)
	elif shape is CapsuleShape3D:
		var cap = shape as CapsuleShape3D
		return Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0)

	# For other shapes, we can't easily scale them
	return Vector3.ONE

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
	print_verbose("%s> pick_up called by %s, is_picked_up: %s" % [name, by.name, is_picked_up()])

	# Handle regular pickup - set the base class mode
	if scalable_second_hand_grab != ScalableSecondHandGrab.SCALE:
		second_hand_grab = scalable_second_hand_grab as SecondHandGrab
	else:
		second_hand_grab = SecondHandGrab.SECOND

	print_verbose("%s> calling super.pick_up, second_hand_grab mode: %s" % [name, second_hand_grab])
	super.pick_up(by)

	# After pickup, check if we should start scaling
	if (scalable_second_hand_grab == ScalableSecondHandGrab.SCALE and
		_grab_driver and _grab_driver.primary and _grab_driver.secondary):
		print_verbose("%s> second grab established, starting scaling" % name)
		_start_scaling_after_grab()

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

# Start scaling after a second grab has been established
func _start_scaling_after_grab():
	if _is_scaling:
		return

	print_verbose("%s> starting scaling after second grab established" % name)
	_is_scaling = true
	_initial_scale_factor = _current_scale_factor
	_target_scale_factor = _current_scale_factor
	_initial_hand_distance = _get_hand_distance()

	print_verbose("%s> initial hand distance: %f" % [name, _initial_hand_distance])

	if _initial_hand_distance <= 0:
		print_verbose("%s> ERROR: initial hand distance is 0, cannot scale" % name)
		_is_scaling = false
		return

	# Calculate center offset for positioning
	if center_while_scaling:
		var center = _get_hands_center()
		_scale_center_offset = global_position - center

	scaling_started.emit(self)

# Stop scaling mode
func _stop_scaling():
	if not _is_scaling:
		return

	print_verbose("%s> stopping scaling at scale factor: %.3f" % [name, _current_scale_factor])
	_is_scaling = false
	scaling_ended.emit(self)

# Update scaling based on hand distance
func _update_scaling(delta: float):
	if not _grab_driver or not _grab_driver.primary or not _grab_driver.secondary:
		print_verbose("%s> stopping scaling - missing grab driver or hands" % name)
		_stop_scaling()
		return

	var current_distance = _get_hand_distance()
	if _initial_hand_distance <= 0:
		print_verbose("%s> stopping scaling - initial hand distance is 0" % name)
		_stop_scaling()
		return

	# Calculate scale factor
	var distance_ratio = current_distance / _initial_hand_distance
	var new_scale_factor = _initial_scale_factor * distance_ratio

	# Clamp scale
	new_scale_factor = clampf(new_scale_factor, min_scale, max_scale)
	_target_scale_factor = new_scale_factor

	# Apply smoothing
	if scale_smoothing > 0.0:
		_current_scale_factor = lerpf(_current_scale_factor, _target_scale_factor, 1.0 - pow(scale_smoothing, delta * 60.0))
	else:
		_current_scale_factor = _target_scale_factor

	# Apply the scaling to collision shapes and meshes
	_apply_scaling(_current_scale_factor)

	# Update mass based on volume scaling if enabled
	if scale_mass_with_volume:
		mass = _original_mass * pow(_current_scale_factor, 3)

	# Update position to keep object centered between hands
	if center_while_scaling:
		_update_center_position()

	print_verbose("%s> scaling update - factor: %.3f, mass: %.2f" % [name, _current_scale_factor, mass])
	scaling_updated.emit(self, _current_scale_factor)

# Apply scaling to all cached collision shapes and mesh instances
func _apply_scaling(scale_factor: float):
	# Scale collision shapes
	for i in range(_collision_shapes.size()):
		var collision_shape = _collision_shapes[i]
		var original_data = _original_collision_data[i]

		if not is_instance_valid(collision_shape) or not collision_shape.shape:
			continue

		_scale_collision_shape(collision_shape.shape, original_data["original_scale"], scale_factor)

	# Scale mesh instances
	for i in range(_mesh_instances.size()):
		var mesh_instance = _mesh_instances[i]
		var original_data = _original_mesh_data[i]

		if not is_instance_valid(mesh_instance):
			continue

		var original_scale = original_data["original_scale"] as Vector3
		mesh_instance.scale = original_scale * scale_factor

# Scale a collision shape based on its type
func _scale_collision_shape(shape: Shape3D, original_scale: Vector3, scale_factor: float):
	if shape is BoxShape3D:
		var box = shape as BoxShape3D
		box.size = original_scale * scale_factor

	elif shape is SphereShape3D:
		var sphere = shape as SphereShape3D
		sphere.radius = (original_scale.x * scale_factor) * 0.5

	elif shape is CylinderShape3D:
		var cylinder = shape as CylinderShape3D
		cylinder.radius = (original_scale.x * scale_factor) * 0.5
		cylinder.height = original_scale.y * scale_factor

	elif shape is CapsuleShape3D:
		var capsule = shape as CapsuleShape3D
		capsule.radius = (original_scale.x * scale_factor) * 0.5
		capsule.height = original_scale.y * scale_factor

# Get distance between the two grabbing hands
func _get_hand_distance() -> float:
	if not _grab_driver:
		print_verbose("%s> no grab driver" % name)
		return 0.0

	if not _grab_driver.primary:
		print_verbose("%s> no primary grab" % name)
		return 0.0

	if not _grab_driver.secondary:
		print_verbose("%s> no secondary grab" % name)
		return 0.0

	var pos1 = _grab_driver.primary.by.global_position
	var pos2 = _grab_driver.secondary.by.global_position
	var distance = pos1.distance_to(pos2)

	return distance

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
	return _current_scale_factor

# Check if currently being scaled
func is_scaling() -> bool:
	return _is_scaling

# Manually set scale factor (useful for initialization or external control)
func set_scale_factor(factor: float):
	factor = clampf(factor, min_scale, max_scale)
	_current_scale_factor = factor
	_target_scale_factor = factor
	_apply_scaling(factor)

	# Update mass if scaling is enabled
	if scale_mass_with_volume:
		mass = _original_mass * pow(factor, 3)
