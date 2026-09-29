@tool
class_name VRMenu
extends LerpPositionPickable

## A floating, grabbable VR panel backed by an [XRToolsViewport2DIn3D].
##
## Spawns in front of the player, animates in with a scale bounce, and
## provides standard grab-to-move behaviour. Designed to host any 2D Control
## scene (settings, dialogs, file pickers) in 3D VR space.
##
## Scene structure:
##   VRMenu (XRToolsPickable / LerpPositionPickable)
##     ├── Viewport2DIn3D (XRToolsViewport2DIn3D)
##     │     └── StaticBody3D (XRToolsPointerEvent target — clicks)
##     │           └── CollisionShape3D (pointer surface)
##     ├── GrabCollision (CollisionShape3D) — whole-surface grab box (FULL mode)
##     ├── EdgeLeft (CollisionShape3D) — left edge grab box (EDGES_ONLY mode)
##     ├── EdgeRight (CollisionShape3D) — right edge grab box (EDGES_ONLY mode)
##     ├── EdgeTop (CollisionShape3D) — top edge grab box (EDGES_ONLY mode)
##     ├── EdgeBottom (CollisionShape3D) — bottom edge grab box (EDGES_ONLY mode)
##     └── PickableHighlight (PickableHighlight) — solid grab highlight
##
## Grab mode can be toggled between EDGES_ONLY (default, prevents accidental grabs)
## and FULL (entire surface is grabbable).

## Grab mode for the menu.
enum GrabMode {
	EDGES_ONLY,  ## Grabbable only by perimeter edges (prevents accidental grabs).
	FULL,        ## Grabbable across the entire surface.
}

## Emitted when the menu is closed (after shrink animation completes).
signal closed

## Emitted when accept is triggered (caller connects as needed).
signal accepted

## Controls whether the menu is grabbable across its entire surface or only by its edges.
@export var grab_mode: GrabMode = GrabMode.EDGES_ONLY:
	set(value):
		grab_mode = value
		_update_grab_colliders()

## Border thickness for edge grabbing (in meters inside the screen perimeter).
@export var edge_thickness: float = 0.1:
	set(value):
		edge_thickness = value
		_update_grab_colliders()

## Extra grab margin outside the screen perimeter (in meters).
@export var grab_margin: float = 0.05:
	set(value):
		grab_margin = value
		_update_grab_colliders()

## The 2D Control being displayed.
var _content: Control = null

## Reference to the Viewport2DIn3D child.
@onready var _viewport_2d: XRToolsViewport2DIn3D = $Viewport2DIn3D

## Reference to the highlight indicator.
@onready var _highlight: PickableHighlight = get_node_or_null("PickableHighlight")

## Animation tween.
var _tween: Tween

## Whether the menu is currently closing.
var _is_closing: bool = false

## Whether grabbing is enabled for this menu.
var _grabbable: bool = true

## If true, the content Control is removed from the viewport before the menu
## is freed — keeping it alive for reuse (e.g., NetworkGateway).
var _preserve_content: bool = false

## Current screen size of the menu in meters.
var _screen_size := Vector2(2.0, 1.2)


func _ready() -> void:
	super._ready()

	_ensure_colliders()
	_update_grab_colliders()

	if _highlight:
		_highlight.style = PickableHighlight.HighlightStyle.SOLID

	if Engine.is_editor_hint():
		return

	# Configure as a floating, non-physics object
	gravity_scale = 0.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	# XRToolsPickable config: hold to grab, restore frozen when released
	press_to_hold = true
	release_mode = ReleaseMode.FROZEN

	# Flat panel: turn to face the hand on ranged grabs (from LerpPositionPickable)
	preserve_orientation = false


## Configure the menu with a Control scene and optional parameters.
##
## [param control] — The Control node to display in the viewport.
## [param options] — Dictionary of setup options:
##   "screen_size": Vector2 (metres, default (2.0, 1.2))
##   "viewport_size": Vector2 (pixels, default (1024, 614))
##   "unshaded": bool (default true)
##   "grabbable": bool (default true)
##   "grab_mode": GrabMode (default GrabMode.EDGES_ONLY)
##   "edge_grab_only": bool (convenience/legacy alias for GrabMode.EDGES_ONLY)
##   "edge_thickness": float (metres, default 0.1)
##   "grab_margin": float (metres, default 0.05)
##   "preserve_content": bool (default false) — if true, reparents content
##     out of the viewport on close so caller can reuse it.
func setup(control: Control, options: Dictionary = {}) -> void:
	_ensure_colliders()
	_content = control

	var screen_sz: Vector2 = options.get("screen_size", Vector2(2.0, 1.2))
	var viewport_sz: Vector2 = options.get("viewport_size", Vector2(1024, 614))
	_grabbable = options.get("grabbable", true)
	enabled = _grabbable
	_preserve_content = options.get("preserve_content", false)

	if options.has("edge_thickness"):
		edge_thickness = options.get("edge_thickness")
	if options.has("grab_margin"):
		grab_margin = options.get("grab_margin")

	if options.has("grab_mode"):
		grab_mode = options.get("grab_mode")
	elif options.has("edge_grab_only"):
		grab_mode = GrabMode.EDGES_ONLY if options.get("edge_grab_only") else GrabMode.FULL

	_screen_size = screen_sz

	# Apply to Viewport2DIn3D
	_viewport_2d.screen_size = screen_sz
	_viewport_2d.viewport_size = viewport_sz
	if options.has("unshaded"):
		_viewport_2d.unshaded = options.get("unshaded")

	# Pointer body must match the screen size for raycast clicks to register.
	var pointer_body: StaticBody3D = _viewport_2d.get_node_or_null("StaticBody3D")
	if pointer_body:
		var pointer_shape: CollisionShape3D = pointer_body.get_node_or_null("CollisionShape3D")
		if pointer_shape and pointer_shape.shape is BoxShape3D:
			pointer_shape.shape.size = Vector3(screen_sz.x, screen_sz.y, 0.02)
		pointer_body.collision_layer = 0b0000_0000_0101_0000_0000_0000_0000_0000
		pointer_body.collision_mask = 0

	_update_grab_colliders()

	# Add the Control to the viewport and wire up the Viewport2DIn3D render
	# pipeline. Normally Viewport2DIn3D expects a PackedScene set via its
	# `scene` property. Since we inject an already-instantiated Control, we
	# need to manually:
	#  1. Add the control to the SubViewport
	#  2. Tell Viewport2DIn3D about the scene_node
	#  3. Force a full render refresh so material + albedo texture are wired
	var viewport: SubViewport = _viewport_2d.get_node_or_null("Viewport")
	if viewport and control:
		if control.get_parent():
			control.get_parent().remove_child(control)
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Spawn into the MarginContainer (margin border for all menus) if present
		var content_parent: Node = viewport.get_node_or_null("Panel/MarginContainer")
		if not content_parent:
			content_parent = viewport
		content_parent.add_child(control)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

		# Let Viewport2DIn3D know this is the active scene content
		_viewport_2d.scene_node = control

		# Force render update to wire albedo texture onto the screen mesh.
		# Exclude _DIRTY_SCENE — we manually injected the control above;
		# the scene handler would remove and destroy it.
		_viewport_2d._dirty = _viewport_2d._DIRTY_ALL & ~_viewport_2d._DIRTY_SCENE
		_viewport_2d._update_render()


## Return the displayed Control.
func get_content() -> Control:
	return _content


## Return the Viewport2DIn3D instance.
func get_viewport_2d() -> XRToolsViewport2DIn3D:
	return _viewport_2d


## Ensures all grab collision shape nodes exist under the VRMenu.
func _ensure_colliders() -> void:
	var grab_shape: CollisionShape3D = get_node_or_null("GrabCollision")
	if not grab_shape:
		grab_shape = CollisionShape3D.new()
		grab_shape.name = "GrabCollision"
		grab_shape.shape = BoxShape3D.new()
		add_child(grab_shape)
	elif not grab_shape.shape or not (grab_shape.shape is BoxShape3D):
		grab_shape.shape = BoxShape3D.new()

	var edge_names := ["EdgeLeft", "EdgeRight", "EdgeTop", "EdgeBottom"]
	for edge_name in edge_names:
		var edge_shape: CollisionShape3D = get_node_or_null(edge_name)
		if not edge_shape:
			edge_shape = CollisionShape3D.new()
			edge_shape.name = edge_name
			edge_shape.shape = BoxShape3D.new()
			add_child(edge_shape)
		elif not edge_shape.shape or not (edge_shape.shape is BoxShape3D):
			edge_shape.shape = BoxShape3D.new()


## Updates collision shape sizes and enabled states to reflect current grab mode and screen size.
func _update_grab_colliders() -> void:
	var grab_shape: CollisionShape3D = get_node_or_null("GrabCollision")
	var edge_left: CollisionShape3D = get_node_or_null("EdgeLeft")
	var edge_right: CollisionShape3D = get_node_or_null("EdgeRight")
	var edge_top: CollisionShape3D = get_node_or_null("EdgeTop")
	var edge_bottom: CollisionShape3D = get_node_or_null("EdgeBottom")

	if not grab_shape or not edge_left or not edge_right or not edge_top or not edge_bottom:
		return

	var w := _screen_size.x
	var h := _screen_size.y
	var depth := 0.05
	var z_pos := -0.04

	var outer_w := w + 2.0 * grab_margin
	var outer_h := h + 2.0 * grab_margin
	var t := minf(edge_thickness + grab_margin, minf(outer_w, outer_h) * 0.45)

	if grab_mode == GrabMode.FULL:
		grab_shape.disabled = not _grabbable
		var box: BoxShape3D = grab_shape.shape
		box.size = Vector3(outer_w, outer_h, depth)
		grab_shape.position = Vector3(0.0, 0.0, z_pos)

		edge_left.disabled = true
		edge_right.disabled = true
		edge_top.disabled = true
		edge_bottom.disabled = true
	else:
		# EDGES_ONLY mode
		grab_shape.disabled = true

		edge_left.disabled = not _grabbable
		edge_right.disabled = not _grabbable
		edge_top.disabled = not _grabbable
		edge_bottom.disabled = not _grabbable

		if _grabbable:
			# Left and Right edges span full outer height
			var lr_size := Vector3(t, outer_h, depth)
			var left_box: BoxShape3D = edge_left.shape
			left_box.size = lr_size
			edge_left.position = Vector3(-outer_w * 0.5 + t * 0.5, 0.0, z_pos)

			var right_box: BoxShape3D = edge_right.shape
			right_box.size = lr_size
			edge_right.position = Vector3(outer_w * 0.5 - t * 0.5, 0.0, z_pos)

			# Top and Bottom edges fit between left and right edges
			var tb_width := maxf(0.01, outer_w - 2.0 * t)
			var tb_size := Vector3(tb_width, t, depth)

			var top_box: BoxShape3D = edge_top.shape
			top_box.size = tb_size
			edge_top.position = Vector3(0.0, outer_h * 0.5 - t * 0.5, z_pos)

			var bottom_box: BoxShape3D = edge_bottom.shape
			bottom_box.size = tb_size
			edge_bottom.position = Vector3(0.0, -outer_h * 0.5 + t * 0.5, z_pos)

	if _highlight:
		_highlight.outline_each_shape = (grab_mode == GrabMode.EDGES_ONLY)
		_highlight.style = PickableHighlight.HighlightStyle.SOLID
		if _highlight.visible:
			_highlight._rebuild()


## Generates a single unified highlight mesh for the whole edge region (EDGES_ONLY)
## or full surface (FULL). Eliminates internal partitions and overlapping corner faces.
func _create_highlight_mesh(hl_style: int, hl_margin: float) -> Mesh:
	if not _grabbable:
		return null

	var outer_w := _screen_size.x + 2.0 * grab_margin
	var outer_h := _screen_size.y + 2.0 * grab_margin
	var depth := 0.05
	var z_pos := -0.04

	var x_out := outer_w * 0.5 + hl_margin
	var y_out := outer_h * 0.5 + hl_margin
	var z_front := z_pos + depth * 0.5 + hl_margin
	var z_back := z_pos - depth * 0.5 - hl_margin

	var im := ImmediateMesh.new()

	if grab_mode == GrabMode.FULL:
		# Single cuboid representing the entire menu surface
		if hl_style == PickableHighlight.HighlightStyle.SOLID:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			var box := AABB(
				Vector3(-x_out, -y_out, z_back),
				Vector3(x_out * 2.0, y_out * 2.0, z_front - z_back)
			)
			for idx in PickableHighlight.BOX_TRIANGLES:
				im.surface_add_vertex(box.get_endpoint(idx))
			im.surface_end()
		else:
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var box := AABB(
				Vector3(-x_out, -y_out, z_back),
				Vector3(x_out * 2.0, y_out * 2.0, z_front - z_back)
			)
			for e in PickableHighlight.BOX_EDGES:
				im.surface_add_vertex(box.get_endpoint(e[0]))
				im.surface_add_vertex(box.get_endpoint(e[1]))
			im.surface_end()
		return im

	# EDGES_ONLY mode: Single unified hollow picture-frame mesh
	var t := minf(edge_thickness + grab_margin, minf(outer_w, outer_h) * 0.45)
	var x_in := maxf(0.01, x_out - (t + 2.0 * hl_margin))
	var y_in := maxf(0.01, y_out - (t + 2.0 * hl_margin))

	# 4 outer corners (front) [0: BL, 1: BR, 2: TR, 3: TL]
	var o_f := [
		Vector3(-x_out, -y_out, z_front),
		Vector3( x_out, -y_out, z_front),
		Vector3( x_out,  y_out, z_front),
		Vector3(-x_out,  y_out, z_front),
	]
	# 4 inner corners (front)
	var i_f := [
		Vector3(-x_in, -y_in, z_front),
		Vector3( x_in, -y_in, z_front),
		Vector3( x_in,  y_in, z_front),
		Vector3(-x_in,  y_in, z_front),
	]
	# 4 outer corners (back)
	var o_b := [
		Vector3(-x_out, -y_out, z_back),
		Vector3( x_out, -y_out, z_back),
		Vector3( x_out,  y_out, z_back),
		Vector3(-x_out,  y_out, z_back),
	]
	# 4 inner corners (back)
	var i_b := [
		Vector3(-x_in, -y_in, z_back),
		Vector3( x_in, -y_in, z_back),
		Vector3( x_in,  y_in, z_back),
		Vector3(-x_in,  y_in, z_back),
	]

	if hl_style == PickableHighlight.HighlightStyle.SOLID:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

		# 1. Front face (4 quads, normals +Z)
		for i in range(4):
			var nxt := (i + 1) % 4
			_add_quad(im, o_f[i], o_f[nxt], i_f[nxt], i_f[i])

		# 2. Back face (4 quads, normals -Z)
		for i in range(4):
			var nxt := (i + 1) % 4
			_add_quad(im, o_b[nxt], o_b[i], i_b[i], i_b[nxt])

		# 3. Outer sides (4 quads, normals facing outward)
		for i in range(4):
			var nxt := (i + 1) % 4
			_add_quad(im, o_f[nxt], o_f[i], o_b[i], o_b[nxt])

		# 4. Inner sides (4 quads, normals facing inward toward cutout)
		for i in range(4):
			var nxt := (i + 1) % 4
			_add_quad(im, i_f[i], i_f[nxt], i_b[nxt], i_b[i])

		im.surface_end()
	else:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(4):
			var nxt := (i + 1) % 4
			# Outer front loop
			im.surface_add_vertex(o_f[i])
			im.surface_add_vertex(o_f[nxt])
			# Inner front loop
			im.surface_add_vertex(i_f[i])
			im.surface_add_vertex(i_f[nxt])
			# Outer back loop
			im.surface_add_vertex(o_b[i])
			im.surface_add_vertex(o_b[nxt])
			# Inner back loop
			im.surface_add_vertex(i_b[i])
			im.surface_add_vertex(i_b[nxt])
			# Outer corner connectors
			im.surface_add_vertex(o_f[i])
			im.surface_add_vertex(o_b[i])
			# Inner corner connectors
			im.surface_add_vertex(i_f[i])
			im.surface_add_vertex(i_b[i])
		im.surface_end()

	return im


static func _add_quad(im: ImmediateMesh, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	# Triangle 1: p0 -> p1 -> p2
	im.surface_add_vertex(p0)
	im.surface_add_vertex(p1)
	im.surface_add_vertex(p2)
	# Triangle 2: p0 -> p2 -> p3
	im.surface_add_vertex(p0)
	im.surface_add_vertex(p2)
	im.surface_add_vertex(p3)


## Tests if a 2D point (in local menu coordinates) is within the edge grab border.
func _is_point_on_edge(local_pt: Vector2) -> bool:
	var outer_w := _screen_size.x + 2.0 * grab_margin
	var outer_h := _screen_size.y + 2.0 * grab_margin
	var t := minf(edge_thickness + grab_margin, minf(outer_w, outer_h) * 0.45)

	var half_w := outer_w * 0.5
	var half_h := outer_h * 0.5
	var inner_half_w := half_w - t
	var inner_half_h := half_h - t

	# Outside the menu outer bounds
	if absf(local_pt.x) > half_w or absf(local_pt.y) > half_h:
		return false

	# Inside outer bounds, but outside inner hollow bounds
	return absf(local_pt.x) >= inner_half_w or absf(local_pt.y) >= inner_half_h


## Tests if a node (controller / pickup) is pointing its forward ray directly at the edge grab region.
func _is_aiming_at_edge(by: Node3D) -> bool:
	var controller := XRHelpers.get_xr_controller(by)
	var ray_node: Node3D = controller if controller else by

	var ray_origin := ray_node.global_position
	var ray_dir := -ray_node.global_transform.basis.z.normalized()

	var local_origin := to_local(ray_origin)
	var local_dir := (global_transform.basis.inverse() * ray_dir).normalized()

	# Must be pointing toward the plane z = 0
	if absf(local_dir.z) < 1e-4:
		return false

	var t_plane := -local_origin.z / local_dir.z
	# Must hit in front of the hand (t_plane > 0) and within reasonable range (15m)
	if t_plane <= 0.0 or t_plane > 15.0:
		return false

	var hit_local := Vector2(
		local_origin.x + local_dir.x * t_plane,
		local_origin.y + local_dir.y * t_plane
	)
	return _is_point_on_edge(hit_local)


## Tests if a hand is close enough to directly touch/grab the edge.
func _is_hand_touching_edge(by: Node3D) -> bool:
	var local_pos := to_local(by.global_position)
	# Within 25cm in Z from the menu surface
	if absf(local_pos.z) > 0.25:
		return false

	var outer_w := _screen_size.x + 2.0 * grab_margin
	var outer_h := _screen_size.y + 2.0 * grab_margin
	var t := minf(edge_thickness + grab_margin, minf(outer_w, outer_h) * 0.45)
	var half_w := outer_w * 0.5 + 0.05
	var half_h := outer_h * 0.5 + 0.05
	var inner_half_w := outer_w * 0.5 - t - 0.02
	var inner_half_h := outer_h * 0.5 - t - 0.02

	var pt := Vector2(local_pos.x, local_pos.y)
	if absf(pt.x) > half_w or absf(pt.y) > half_h:
		return false
	return absf(pt.x) >= inner_half_w or absf(pt.y) >= inner_half_h


## Test if this pickable is currently held by the specified node.
func is_picked_up_by(by: Node3D) -> bool:
	if not _grab_driver:
		return false
	if _grab_driver.primary and (_grab_driver.primary.by == by or _grab_driver.primary.pickup == by):
		return true
	if _grab_driver.secondary and (_grab_driver.secondary.by == by or _grab_driver.secondary.pickup == by):
		return true
	return false


## Overridden from XRToolsPickable.
## In EDGES_ONLY mode, only permits grabbing when aiming directly at the edge grab region
## (direct laser/pointer ray) or when directly touching the edge with the hand.
func can_pick_up(by: Node3D) -> bool:
	if not _grabbable:
		return false

	if not super.can_pick_up(by):
		return false

	if is_picked_up_by(by) or grab_mode == GrabMode.FULL:
		return true

	return _is_aiming_at_edge(by) or _is_hand_touching_edge(by)


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
		var parent := _content.get_parent()
		if parent:
			parent.remove_child(_content)
	closed.emit()
	queue_free()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
