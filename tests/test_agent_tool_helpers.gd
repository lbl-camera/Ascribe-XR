extends GdUnitTestSuite


# validate_tool(name, args) -> "" if ok, else an error string.


func test_load_specimen_valid():
	assert_that(AgentToolHelpers.validate_tool("load_specimen", {"specimen_id": "abc"})).is_equal("")


func test_load_specimen_missing_key():
	assert_that(AgentToolHelpers.validate_tool("load_specimen", {})).is_not_equal("")


func test_load_specimen_wrong_type():
	assert_that(AgentToolHelpers.validate_tool("load_specimen", {"specimen_id": 5})).is_not_equal("")


func test_set_active_specimen_valid():
	assert_that(AgentToolHelpers.validate_tool("set_active_specimen", {"index": 0})).is_equal("")


func test_set_active_specimen_wrong_type():
	assert_that(AgentToolHelpers.validate_tool("set_active_specimen", {"index": "0"})).is_not_equal("")


func test_set_active_specimen_missing_key():
	assert_that(AgentToolHelpers.validate_tool("set_active_specimen", {})).is_not_equal("")


func test_remove_specimen_valid():
	assert_that(AgentToolHelpers.validate_tool("remove_specimen", {"index": 2})).is_equal("")


func test_remove_specimen_missing_key():
	assert_that(AgentToolHelpers.validate_tool("remove_specimen", {})).is_not_equal("")


func test_set_room_scene_valid():
	for room in ["lab", "black", "passthrough", "world_scale"]:
		assert_that(AgentToolHelpers.validate_tool("set_room_scene", {"name": room})).is_equal("")


func test_set_room_scene_bad_enum():
	assert_that(AgentToolHelpers.validate_tool("set_room_scene", {"name": "space"})).is_not_equal("")


func test_set_room_scene_missing_key():
	assert_that(AgentToolHelpers.validate_tool("set_room_scene", {})).is_not_equal("")


func test_set_display_param_valid():
	for name in ["gamma", "opacity", "color_scalar", "max_steps", "step_size", "zoom"]:
		assert_that(AgentToolHelpers.validate_tool("set_display_param", {"index": 0, "name": name, "value": 1.0})).is_equal("")


func test_set_display_param_bad_enum():
	assert_that(AgentToolHelpers.validate_tool("set_display_param", {"index": 0, "name": "bogus", "value": 1.0})).is_not_equal("")


func test_set_display_param_missing_key():
	assert_that(AgentToolHelpers.validate_tool("set_display_param", {"index": 0, "name": "gamma"})).is_not_equal("")


func test_set_display_param_wrong_type_index():
	assert_that(AgentToolHelpers.validate_tool("set_display_param", {"index": "0", "name": "gamma", "value": 1.0})).is_not_equal("")


func test_set_display_param_wrong_type_value():
	assert_that(AgentToolHelpers.validate_tool("set_display_param", {"index": 0, "name": "gamma", "value": "1.0"})).is_not_equal("")


func test_capture_viewport_valid():
	assert_that(AgentToolHelpers.validate_tool("capture_viewport", {})).is_equal("")


func test_unknown_tool_name():
	assert_that(AgentToolHelpers.validate_tool("frobnicate", {})).is_not_equal("")
