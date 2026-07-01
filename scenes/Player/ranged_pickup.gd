@tool
class_name XRToolsRangedPickupBeam
extends XRToolsFunctionPickup


## Ranged pickup as a fixed-radius beam.
##
## The stock [XRToolsFunctionPickup] builds the ranged-grab volume as a cone
## (radius = tan(ranged_angle) * ranged_distance) and then selects the object
## whose *pivot* is most aligned with the hand's forward axis, ignoring
## distance. That has two bad consequences: at wide angles it grabs whatever
## off-axis pivot happens to line up best (not what you point at), and at
## narrow angles an extended object's pivot falls outside the cone so you can
## grab nothing.
##
## This subclass replaces both halves:
##   * the ranged volume is a constant-radius beam (see [member ranged_radius]),
##   * selection picks the candidate whose collider BOUNDING BOX is closest to
##     the hand.
##
## Ranking by bounding box (rather than pivot) means a large object you point
## at the edge of is treated as near, not far. The inherited [code]ranged_angle[/code]
## property no longer has any effect.


## Radius of the ranged-grab beam, in metres. Smaller = a tighter beam you must
## aim more precisely; the beam length is still controlled by ranged_distance.
@export var ranged_radius : float = 0.5: set = _set_ranged_radius


# Cache of per-shape LOCAL-space AABBs, keyed by Shape3D instance id. Collider
# geometry doesn't change at runtime, so the debug-mesh bounds are computed once.
var _shape_aabb_cache : Dictionary = {}


# Called when the beam radius has been modified
func _set_ranged_radius(new_value: float) -> void:
	ranged_radius = new_value
	if is_inside_tree():
		_update_colliders()


# Build the ranged volume as a fixed-radius beam instead of a cone.
func _update_colliders() -> void:
	# Let the base class size the grab sphere and the beam length/position.
	super._update_colliders()

	# Override the cone radius with our constant beam radius.
	if _ranged_collision:
		_ranged_collision.shape.radius = ranged_radius


# Select the ranged candidate whose collider bounding box is closest to the
# hand, rather than the one whose pivot is most aligned with the forward axis.
func _get_closest_ranged() -> Node3D:
	var new_closest_obj: Node3D = null
	var new_closest_distance := MAX_GRAB_DISTANCE2
	var hand_pos := global_transform.origin
	for o in _object_in_ranged_area:
		# skip objects that can not be picked up
		if not o.can_pick_up(self):
			continue

		# Distance to the nearest point of the collider bounding box, falling
		# back to the pivot if the object has no usable collision shapes.
		var box := _object_world_aabb(o)
		var distance_squared: float
		if box.size == Vector3.ZERO:
			distance_squared = hand_pos.distance_squared_to(o.global_transform.origin)
		else:
			distance_squared = hand_pos.distance_squared_to(_closest_point_on_aabb(hand_pos, box))

		# Save if this object is closer than the current best
		if distance_squared < new_closest_distance:
			new_closest_obj = o
			new_closest_distance = distance_squared

	# Return best object
	return new_closest_obj


# World-space AABB enclosing all of the object's (enabled) collision shapes.
# Returns a zero-size AABB if none are found.
func _object_world_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var have_box := false
	for cs in _find_collision_shapes(node):
		var world_box: AABB = cs.global_transform * _collider_local_aabb(cs)
		if not have_box:
			result = world_box
			have_box = true
		else:
			result = result.merge(world_box)
	return result


# Recursively collect enabled CollisionShape3D nodes under the given node.
func _find_collision_shapes(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is CollisionShape3D and not child.disabled:
			out.append(child)
		out.append_array(_find_collision_shapes(child))
	return out


# Local-space AABB of a collision shape, computed once from its debug mesh and
# cached. Works for any Shape3D type.
func _collider_local_aabb(cs: CollisionShape3D) -> AABB:
	var shape := cs.shape
	if shape == null:
		return AABB()

	var id := shape.get_instance_id()
	if _shape_aabb_cache.has(id):
		return _shape_aabb_cache[id]

	var mesh := shape.get_debug_mesh()
	var aabb: AABB = mesh.get_aabb() if mesh else AABB()
	_shape_aabb_cache[id] = aabb
	return aabb


# Closest point to p that lies inside (or on) the axis-aligned box.
func _closest_point_on_aabb(p: Vector3, box: AABB) -> Vector3:
	var mn := box.position
	var mx := box.position + box.size
	return Vector3(
		clampf(p.x, mn.x, mx.x),
		clampf(p.y, mn.y, mx.y),
		clampf(p.z, mn.z, mx.z))
