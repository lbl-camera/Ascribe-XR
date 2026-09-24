@tool
class_name PickableHighlight
extends MeshInstance3D

## Draws a wireframe box around the parent pickable while it is highlighted.
##
## Add as a child of any XRToolsPickable. XRToolsFunctionPickup requests a
## highlight on the object it would grab next, so this shows the user which
## pickable a grab will take before they squeeze. The box is fitted to the
## parent's BoxShape3D collision shapes each time the highlight turns on, so it
## tracks runtime rescaling.

## Outline color
@export var color := Color(1.0, 0.85, 0.2, 1.0)

## Extra margin around the collision bounds, in meters
@export var margin := 0.01

## Hide the outline while the pickable is held
@export var hide_when_held := true


func _ready() -> void:
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	material_override = mat
	if Engine.is_editor_hint():
		return
	var parent := get_parent()
	if parent and parent.has_signal("highlight_updated"):
		parent.highlight_updated.connect(_on_highlight_updated)
	if parent and parent.has_signal("picked_up"):
		parent.picked_up.connect(func(_p): if hide_when_held: visible = false)


func _on_highlight_updated(pickable: Node, enable: bool) -> void:
	if enable and hide_when_held and pickable.has_method("is_picked_up") \
			and pickable.is_picked_up():
		enable = false
	if enable:
		_rebuild()
	visible = enable


# Build a line box around the union of the parent's box collision shapes
func _rebuild() -> void:
	var parent := get_parent() as Node3D
	var bounds := AABB()
	var first := true
	for child in parent.get_children():
		var cs := child as CollisionShape3D
		if not cs or cs.disabled or not cs.shape is BoxShape3D:
			continue
		var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var box := cs.transform * AABB(-half, half * 2.0)
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		mesh = null
		return
	bounds = bounds.grow(margin)

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4],
			[0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(bounds.get_endpoint(e[0]))
		im.surface_add_vertex(bounds.get_endpoint(e[1]))
	im.surface_end()
	mesh = im
