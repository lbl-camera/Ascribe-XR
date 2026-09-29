@tool
class_name PickableHighlight
extends MeshInstance3D

## Draws a highlight indicator around the parent pickable while it is highlighted.
##
## Add as a child of any XRToolsPickable. XRToolsFunctionPickup requests a
## highlight on the object it would grab next, so this shows the user which
## pickable a grab will take before they squeeze. The box is fitted to the
## parent's collision shapes (any type) each time the highlight turns on, so it
## tracks runtime rescaling. A held object stays outlined only while another
## hand targets it (the holder clears its own highlight request on pickup).
## The color says which hand is targeting it (see [method color_for]).

## Highlight display style.
enum HighlightStyle {
	WIREFRAME,   ## Wireframe lines outlining the shape(s).
	SOLID,       ## Translucent filled surfaces covering the shape(s).
}

## Highlight colors by requesting hand, shared with custom highlight effects
const LEFT_COLOR := Color(0.3, 0.8, 1.0, 1.0)
const RIGHT_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const BOTH_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## Line box edge index pairs (12 edges of a cube/box)
const BOX_EDGES: Array = [
	[0, 1], [1, 3], [3, 2], [2, 0],
	[4, 5], [5, 7], [7, 6], [6, 4],
	[0, 4], [1, 5], [2, 6], [3, 7]
]

## Triangle vertex indices for the 6 faces of a box (12 triangles with CCW outward normals)
const BOX_TRIANGLES: Array = [
	0, 1, 3,  0, 3, 2, # X min
	4, 6, 7,  4, 7, 5, # X max
	0, 4, 5,  0, 5, 1, # Y min
	2, 3, 7,  2, 7, 6, # Y max
	0, 2, 6,  0, 6, 4, # Z min
	1, 5, 7,  1, 7, 3  # Z max
]

## Extra margin around the collision bounds, in meters
@export var margin := 0.01

## If true, draws separate shapes around each enabled collision shape
## instead of a single box around their union.
@export var outline_each_shape := false

## Display style: wireframe lines or translucent filled solid
@export var style: HighlightStyle = HighlightStyle.WIREFRAME:
	set(value):
		style = value
		_update_material_settings()
		if visible:
			_rebuild()
			_update_color()

## Alpha transparency for SOLID highlight style
@export var fill_alpha: float = 0.35:
	set(value):
		fill_alpha = value
		if visible:
			_update_color()

## If true, culls back-facing triangles so only the front-most facing surface draws
@export var cull_back_faces: bool = true:
	set(value):
		cull_back_faces = value
		_update_material_settings()


func _ready() -> void:
	visible = false
	set_process(false)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	material_override = mat
	_update_material_settings()
	if Engine.is_editor_hint():
		return
	var parent := get_parent()
	if parent and parent.has_signal("highlight_updated"):
		parent.highlight_updated.connect(_on_highlight_updated)


func _update_material_settings() -> void:
	var mat := material_override as StandardMaterial3D
	if not mat:
		return
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK if cull_back_faces else BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	if style == HighlightStyle.SOLID:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


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
	var mat := material_override as StandardMaterial3D
	if not mat:
		return
	var c := color_for(get_parent())
	if style == HighlightStyle.SOLID and c != Color.TRANSPARENT:
		mat.albedo_color = Color(c.r, c.g, c.b, fill_alpha)
	else:
		mat.albedo_color = c


# Build mesh box(es) around the parent's collision shape bounds
func _rebuild() -> void:
	var parent := get_parent() as Node3D
	if not parent:
		mesh = null
		return

	if parent.has_method("_create_highlight_mesh"):
		mesh = parent._create_highlight_mesh(style, margin)
		return

	var primitive := Mesh.PRIMITIVE_TRIANGLES if style == HighlightStyle.SOLID else Mesh.PRIMITIVE_LINES

	if outline_each_shape:
		var im := ImmediateMesh.new()
		im.surface_begin(primitive)
		var count := 0
		for child in parent.get_children():
			var cs := child as CollisionShape3D
			if not cs or cs.disabled or not cs.shape:
				continue
			var debug_mesh := cs.shape.get_debug_mesh()
			if not debug_mesh:
				continue
			var box: AABB = (cs.transform * debug_mesh.get_aabb()).grow(margin)
			count += 1
			if style == HighlightStyle.SOLID:
				for idx in BOX_TRIANGLES:
					im.surface_add_vertex(box.get_endpoint(idx))
			else:
				for e in BOX_EDGES:
					im.surface_add_vertex(box.get_endpoint(e[0]))
					im.surface_add_vertex(box.get_endpoint(e[1]))
		im.surface_end()
		mesh = im if count > 0 else null
		return

	var bounds := AABB()
	var first := true
	for child in parent.get_children():
		var cs := child as CollisionShape3D
		if not cs or cs.disabled or not cs.shape:
			continue
		var debug_mesh := cs.shape.get_debug_mesh()
		if not debug_mesh:
			continue
		var box: AABB = cs.transform * debug_mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		mesh = null
		return
	bounds = bounds.grow(margin)

	var im := ImmediateMesh.new()
	im.surface_begin(primitive)
	if style == HighlightStyle.SOLID:
		for idx in BOX_TRIANGLES:
			im.surface_add_vertex(bounds.get_endpoint(idx))
	else:
		for e in BOX_EDGES:
			im.surface_add_vertex(bounds.get_endpoint(e[0]))
			im.surface_add_vertex(bounds.get_endpoint(e[1]))
	im.surface_end()
	mesh = im
