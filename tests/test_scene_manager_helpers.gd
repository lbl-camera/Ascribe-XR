extends GdUnitTestSuite


# next_active_after_remove rules (from spec):
# - If list becomes empty after the remove, return -1.
# - If the removed index is the active one, return the index of the
#   most-recently-added remaining specimen (i.e., new last index).
# - If the removed index is before the active one, active shifts down by 1.
# - If the removed index is after the active one, active stays put.


func test_remove_only_specimen_returns_minus_one():
	var result = SceneManagerHelpers.next_active_after_remove(1, 0, 0)
	assert_that(result).is_equal(-1)


func test_remove_active_with_others_picks_new_last_index():
	# 3 specimens, active=1, remove index 1 -> remaining size 2, new active = 1 (last)
	var result = SceneManagerHelpers.next_active_after_remove(3, 1, 1)
	assert_that(result).is_equal(1)


func test_remove_active_at_end_picks_new_last_index():
	# 3 specimens, active=2, remove index 2 -> remaining size 2, new active = 1 (last)
	var result = SceneManagerHelpers.next_active_after_remove(3, 2, 2)
	assert_that(result).is_equal(1)


func test_remove_below_active_shifts_active_down():
	# 3 specimens, active=2, remove index 0 -> active becomes 1
	var result = SceneManagerHelpers.next_active_after_remove(3, 0, 2)
	assert_that(result).is_equal(1)


func test_remove_above_active_leaves_active_alone():
	# 3 specimens, active=0, remove index 2 -> active stays 0
	var result = SceneManagerHelpers.next_active_after_remove(3, 2, 0)
	assert_that(result).is_equal(0)


# can_load_with_scale_mode rules:
# - Empty list: any scale mode allowed.
# - Non-empty list: only the existing list's scale mode is allowed.


func test_can_load_with_scale_mode_empty_list_allows_anything():
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([], Specimen.ScaleMode.TABLE)).is_true()
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([], Specimen.ScaleMode.WORLD)).is_true()


func test_can_load_with_scale_mode_matching_existing():
	var spec := _make_dummy_specimen(Specimen.ScaleMode.TABLE)
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([spec], Specimen.ScaleMode.TABLE)).is_true()
	spec.queue_free()


func test_can_load_with_scale_mode_rejects_mismatch():
	var spec := _make_dummy_specimen(Specimen.ScaleMode.TABLE)
	assert_that(SceneManagerHelpers.can_load_with_scale_mode([spec], Specimen.ScaleMode.WORLD)).is_false()
	spec.queue_free()


func _make_dummy_specimen(mode: int) -> Specimen:
	var s := Specimen.new()
	s.scale_mode = mode
	return s


# resolve_specimen_type rules:
# - The runtime result type (from the completed job) is authoritative.
# - Empty result type falls back to the catalog metadata type.
# - Both empty falls back to "mesh".


func test_resolve_specimen_type_result_overrides_catalog():
	# AI Generate is advertised as "mesh" in the catalog but produced a volume.
	assert_that(SceneManagerHelpers.resolve_specimen_type("volume", "mesh")).is_equal("volume")


func test_resolve_specimen_type_falls_back_to_metadata_when_result_empty():
	assert_that(SceneManagerHelpers.resolve_specimen_type("", "volume")).is_equal("volume")


func test_resolve_specimen_type_result_mesh_overrides_catalog_volume():
	assert_that(SceneManagerHelpers.resolve_specimen_type("mesh", "volume")).is_equal("mesh")


func test_resolve_specimen_type_defaults_to_mesh_when_both_empty():
	assert_that(SceneManagerHelpers.resolve_specimen_type("", "")).is_equal("mesh")
