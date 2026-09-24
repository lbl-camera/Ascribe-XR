extends GdUnitTestSuite


func _check(scene_path: String) -> void:
	var root: Node = auto_free(load(scene_path).instantiate())
	add_child(root)
	await await_idle_frame()
	var pickable: Node = root if root.has_method("request_highlight") else root.get_child(0)
	if not pickable.get_children().any(func(c): return c is CollisionShape3D and c.shape is BoxShape3D):
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		pickable.add_child(cs)
	var hl: PickableHighlight = pickable.get_node("PickableHighlight")
	assert_bool(hl.visible).is_false()
	pickable.request_highlight(self, true)
	assert_bool(hl.visible).is_true()
	assert_object(hl.mesh).is_not_null()
	pickable.request_highlight(self, false)
	assert_bool(hl.visible).is_false()


func test_vr_menu_highlight() -> void:
	await _check("res://scenes/UI/vr_menu.tscn")


func test_scalable_pickable_highlight() -> void:
	await _check("res://scenes/pickable/scalable_multiplayer_pickable.tscn")


func test_convex_collider_is_outlined() -> void:
	var root: Node = auto_free(load("res://scenes/pickable/scalable_multiplayer_pickable.tscn").instantiate())
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 1)])
	cs.shape = shape
	root.add_child(cs)
	add_child(root)
	await await_idle_frame()
	var hl: PickableHighlight = root.get_node("PickableHighlight")
	root.request_highlight(self, true)
	assert_bool(hl.visible).is_true()
	assert_object(hl.mesh).is_not_null()
	assert_vector(hl.mesh.get_aabb().size).is_greater(Vector3(1.9, 1.9, 0.9))


func _hand(tracker: StringName) -> Node:
	var controller: XRController3D = auto_free(XRController3D.new())
	controller.tracker = tracker
	var pickup := Node3D.new()
	controller.add_child(pickup)
	return pickup


func test_color_per_hand() -> void:
	var root: Node = auto_free(load("res://scenes/UI/vr_menu.tscn").instantiate())
	add_child(root)
	await await_idle_frame()
	var left := _hand(&"left_hand")
	var right := _hand(&"right_hand")
	root.request_highlight(left, true)
	assert_that(PickableHighlight.color_for(root)).is_equal(PickableHighlight.LEFT_COLOR)
	root.request_highlight(right, true)
	assert_that(PickableHighlight.color_for(root)).is_equal(PickableHighlight.BOTH_COLOR)
	root.request_highlight(left, false)
	assert_that(PickableHighlight.color_for(root)).is_equal(PickableHighlight.RIGHT_COLOR)
