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
