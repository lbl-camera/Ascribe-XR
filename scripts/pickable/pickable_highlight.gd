@tool
class_name PickableHighlight
extends MeshInstance3D

## Draws a wireframe box around the parent pickable while it is highlighted.
##
## Add as a child of any XRToolsPickable. XRToolsFunctionPickup requests a
## highlight on the object it would grab next, so this shows the user which
## pickable a grab will take before they squeeze. The box is fitted to the
## parent's collision shapes (any type) each time the highlight turns on, so it
## tracks runtime rescaling. A held object stays outlined only while another
## hand targets it (the holder clears its own highlight request on pickup).

## Shared highlight color, also used by custom highlight effects
const DEFAULT_COLOR := Color(1.0, 0.85, 0.2, 1.0)

## Outline color
@export var color := DEFAULT_COLOR

## Extra margin around the collision bounds, in meters
@export var margin := 0.01


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


func _on_highlight_updated(_pickable: Node, enable: bool) -> void:
	if enable:
		_rebuild()
	visible = enable


# Build a line box around the union of the parent's collision shape bounds
func _rebuild() -> void:
	var parent := get_parent() as Node3D
	var bounds := AABB()
	var first := true
	for child in parent.get_children():
		var cs := child as CollisionShape3D
		if not cs or cs.disabled or not cs.shape:
			continue
		var box := cs.transform * cs.shape.get_debug_mesh().get_aabb()
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
