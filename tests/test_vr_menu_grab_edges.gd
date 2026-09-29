extends GdUnitTestSuite


func _hand(tracker: StringName) -> Node:
	var controller: XRController3D = auto_free(XRController3D.new())
	controller.tracker = tracker
	var pickup: Node3D = Node3D.new()
	controller.add_child(pickup)
	return pickup


func _make_mock_aim(parent: Node, pos: Vector3, forward: Vector3 = Vector3(0, 0, -1)) -> Node3D:
	var ray_node := Node3D.new()
	parent.add_child(ray_node)
	ray_node.position = pos
	if forward != Vector3.ZERO:
		ray_node.look_at_from_position(pos, pos + forward, Vector3.UP)
	return ray_node


func test_default_grab_mode_is_edges_only() -> void:
	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()

	assert_that(menu.grab_mode).is_equal(VRMenu.GrabMode.EDGES_ONLY)

	var grab_col: CollisionShape3D = menu.get_node("GrabCollision")
	var edge_l: CollisionShape3D = menu.get_node("EdgeLeft")
	var edge_r: CollisionShape3D = menu.get_node("EdgeRight")
	var edge_t: CollisionShape3D = menu.get_node("EdgeTop")
	var edge_b: CollisionShape3D = menu.get_node("EdgeBottom")

	# Full center collider must be disabled
	assert_bool(grab_col.disabled).is_true()

	# 4 edge colliders must be active
	assert_bool(edge_l.disabled).is_false()
	assert_bool(edge_r.disabled).is_false()
	assert_bool(edge_t.disabled).is_false()
	assert_bool(edge_b.disabled).is_false()

	# Pickable highlight should outline each shape and use solid style
	var hl: PickableHighlight = menu.get_node("PickableHighlight")
	assert_bool(hl.outline_each_shape).is_true()
	assert_that(hl.style).is_equal(PickableHighlight.HighlightStyle.SOLID)
	assert_that((hl.material_override as StandardMaterial3D).cull_mode).is_equal(BaseMaterial3D.CULL_BACK)


func test_switch_to_full_grab_mode() -> void:
	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()

	menu.grab_mode = VRMenu.GrabMode.FULL

	var grab_col: CollisionShape3D = menu.get_node("GrabCollision")
	var edge_l: CollisionShape3D = menu.get_node("EdgeLeft")
	var edge_r: CollisionShape3D = menu.get_node("EdgeRight")
	var edge_t: CollisionShape3D = menu.get_node("EdgeTop")
	var edge_b: CollisionShape3D = menu.get_node("EdgeBottom")

	assert_bool(grab_col.disabled).is_false()
	assert_bool(edge_l.disabled).is_true()
	assert_bool(edge_r.disabled).is_true()
	assert_bool(edge_t.disabled).is_true()
	assert_bool(edge_b.disabled).is_true()

	var hl: PickableHighlight = menu.get_node("PickableHighlight")
	assert_bool(hl.outline_each_shape).is_false()

	# Switch back to EDGES_ONLY
	menu.grab_mode = VRMenu.GrabMode.EDGES_ONLY
	assert_bool(grab_col.disabled).is_true()
	assert_bool(edge_l.disabled).is_false()
	assert_bool(edge_r.disabled).is_false()
	assert_bool(edge_t.disabled).is_false()
	assert_bool(edge_b.disabled).is_false()
	assert_bool(hl.outline_each_shape).is_true()


func test_setup_custom_size_and_edge_dimensions() -> void:
	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()

	var dummy_control: Control = auto_free(Control.new())
	var custom_screen := Vector2(3.0, 1.5)
	var custom_thickness := 0.15
	var custom_margin := 0.08

	menu.setup(dummy_control, {
		"screen_size": custom_screen,
		"edge_thickness": custom_thickness,
		"grab_margin": custom_margin,
		"grab_mode": VRMenu.GrabMode.EDGES_ONLY
	})

	var edge_l: CollisionShape3D = menu.get_node("EdgeLeft")
	var edge_r: CollisionShape3D = menu.get_node("EdgeRight")
	var edge_t: CollisionShape3D = menu.get_node("EdgeTop")
	var edge_b: CollisionShape3D = menu.get_node("EdgeBottom")

	var outer_w: float = custom_screen.x + 2.0 * custom_margin
	var outer_h: float = custom_screen.y + 2.0 * custom_margin
	var t: float = custom_thickness + custom_margin

	# Left/Right shapes
	var lr_box: BoxShape3D = edge_l.shape as BoxShape3D
	assert_float(lr_box.size.x).is_equal_approx(t, 0.001)
	assert_float(lr_box.size.y).is_equal_approx(outer_h, 0.001)
	assert_float(edge_l.position.x).is_equal_approx(-outer_w * 0.5 + t * 0.5, 0.001)
	assert_float(edge_r.position.x).is_equal_approx(outer_w * 0.5 - t * 0.5, 0.001)

	# Top/Bottom shapes
	var tb_box: BoxShape3D = edge_t.shape as BoxShape3D
	assert_float(tb_box.size.x).is_equal_approx(outer_w - 2.0 * t, 0.001)
	assert_float(tb_box.size.y).is_equal_approx(t, 0.001)
	assert_float(edge_t.position.y).is_equal_approx(outer_h * 0.5 - t * 0.5, 0.001)
	assert_float(edge_b.position.y).is_equal_approx(-outer_h * 0.5 + t * 0.5, 0.001)


func test_setup_grabbable_false_disables_all() -> void:
	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()

	var dummy_control: Control = auto_free(Control.new())
	menu.setup(dummy_control, {"grabbable": false})

	assert_bool(menu.enabled).is_false()
	assert_bool((menu.get_node("GrabCollision") as CollisionShape3D).disabled).is_true()
	assert_bool((menu.get_node("EdgeLeft") as CollisionShape3D).disabled).is_true()
	assert_bool((menu.get_node("EdgeRight") as CollisionShape3D).disabled).is_true()
	assert_bool((menu.get_node("EdgeTop") as CollisionShape3D).disabled).is_true()
	assert_bool((menu.get_node("EdgeBottom") as CollisionShape3D).disabled).is_true()


func test_edge_highlight_mesh_and_hand_colors() -> void:
	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()

	var hl: PickableHighlight = menu.get_node("PickableHighlight")
	var left: Node = _hand(&"left_hand")
	var right: Node = _hand(&"right_hand")

	# Highlight with left hand
	menu.request_highlight(left, true)
	await await_idle_frame()
	assert_bool(hl.visible).is_true()
	assert_object(hl.mesh).is_not_null()
	var expected_left := Color(PickableHighlight.LEFT_COLOR.r, PickableHighlight.LEFT_COLOR.g, PickableHighlight.LEFT_COLOR.b, hl.fill_alpha)
	assert_that((hl.material_override as StandardMaterial3D).albedo_color).is_equal(expected_left)
	assert_that(PickableHighlight.color_for(menu)).is_equal(PickableHighlight.LEFT_COLOR)

	# Add right hand -> both
	menu.request_highlight(right, true)
	await await_idle_frame()
	var expected_both := Color(PickableHighlight.BOTH_COLOR.r, PickableHighlight.BOTH_COLOR.g, PickableHighlight.BOTH_COLOR.b, hl.fill_alpha)
	assert_that((hl.material_override as StandardMaterial3D).albedo_color).is_equal(expected_both)
	assert_that(PickableHighlight.color_for(menu)).is_equal(PickableHighlight.BOTH_COLOR)

	# Release left -> right only
	menu.request_highlight(left, false)
	await await_idle_frame()
	var expected_right := Color(PickableHighlight.RIGHT_COLOR.r, PickableHighlight.RIGHT_COLOR.g, PickableHighlight.RIGHT_COLOR.b, hl.fill_alpha)
	assert_that((hl.material_override as StandardMaterial3D).albedo_color).is_equal(expected_right)
	assert_that(PickableHighlight.color_for(menu)).is_equal(PickableHighlight.RIGHT_COLOR)

	# Release right -> hidden
	menu.request_highlight(right, false)
	await await_idle_frame()
	assert_bool(hl.visible).is_false()


func test_laser_aim_and_pickup_edges_vs_center() -> void:
	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()

	# Menu default: screen_size (2.0, 1.2), margin 0.05, thickness 0.1
	# outer_w = 2.10, outer_h = 1.30, t = 0.15
	# Right edge spans X: [0.90, 1.05], Y: [-0.65, 0.65]

	# 1. Aim directly at right edge (X = 0.975, Z = 1.0, forward = -Z)
	var aim_edge: Node3D = _make_mock_aim(menu, Vector3(0.975, 0.0, 1.0))
	assert_bool(menu.can_pick_up(aim_edge)).is_true()

	# 2. Aim at center of menu (X = 0.0, Y = 0.0, Z = 1.0, forward = -Z)
	var aim_center: Node3D = _make_mock_aim(menu, Vector3(0.0, 0.0, 1.0))
	assert_bool(menu.can_pick_up(aim_center)).is_false()

	# 3. Aim completely outside menu (X = 1.5, Y = 0.0, Z = 1.0, forward = -Z)
	var aim_outside: Node3D = _make_mock_aim(menu, Vector3(1.5, 0.0, 1.0))
	assert_bool(menu.can_pick_up(aim_outside)).is_false()

	# 4. Direct hand touching the edge (X = 0.975, Y = 0.0, Z = 0.05)
	var hand_touch: Node3D = _make_mock_aim(menu, Vector3(0.975, 0.0, 0.05))
	assert_bool(menu.can_pick_up(hand_touch)).is_true()

	# 5. In FULL grab mode, aiming at center is permitted
	menu.grab_mode = VRMenu.GrabMode.FULL
	assert_bool(menu.can_pick_up(aim_center)).is_true()


# func test_menu_content_is_mounted_in_viewport() -> void:
# 	var menu: VRMenu = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
# 	add_child(menu)
# 	await await_idle_frame()
# 
# 	var control: Control = Button.new()
# 	control.text = "Click Me"
# 	menu.setup(control)
# 
# 	assert_that(menu.get_content()).is_equal(control)
# 	var v2d: XRToolsViewport2DIn3D = menu.get_viewport_2d()
# 	assert_that(v2d.scene_node).is_equal(control)
# 	assert_that(control.get_parent()).is_not_null()
# 	assert_bool(v2d.get_node("Viewport").is_ancestor_of(control)).is_true()
# 