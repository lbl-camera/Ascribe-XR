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
## The color says which hand is targeting it (see [method color_for]).

## Highlight colors by requesting hand, shared with custom highlight effects
const LEFT_COLOR := Color(0.3, 0.8, 1.0, 1.0)
const RIGHT_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const BOTH_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## Extra margin around the collision bounds, in meters
@export var margin := 0.01


func _ready() -> void:
	visible = false
	set_process(false)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	material_override = mat
	if Engine.is_editor_hint():
		return
	var parent := get_parent()
	if parent and parent.has_signal("highlight_updated"):
		parent.highlight_updated.connect(_on_highlight_updated)


# Color for a pickable's current highlight, based on which hand(s) request it
static func color_for(pickable: Node) -> Color:
	var left := false
	var right := false
	for from in pickable.get("_highlight_requests").keys():
		var controller := (from as Node).get_parent() as XRController3D if is_instance_valid(from) else null
		if controller and controller.tracker == &"left_hand":
			left = true
		else:
			right = true
	if left and right:
		return BOTH_COLOR
	return LEFT_COLOR if left else RIGHT_COLOR


func _on_highlight_updated(_pickable: Node, enable: bool) -> void:
	if enable:
		_rebuild()
		_update_color()
	visible = enable
	set_process(enable)


# The requesting hand can change without the highlight toggling
func _process(_delta: float) -> void:
	_update_color()


func _update_color() -> void:
	(material_override as StandardMaterial3D).albedo_color = color_for(get_parent())


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
