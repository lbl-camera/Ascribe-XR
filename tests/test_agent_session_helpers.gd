extends GdUnitTestSuite


func test_build_text_frame():
	var json_text := AgentSessionHelpers.build_text_frame("hello")
	var parsed = JSON.parse_string(json_text)
	assert_that(parsed["type"]).is_equal("text")
	assert_that(parsed["text"]).is_equal("hello")


func test_build_tool_result_frame():
	var json_text := AgentSessionHelpers.build_tool_result_frame("r1", {"ok": true})
	var parsed = JSON.parse_string(json_text)
	assert_that(parsed["type"]).is_equal("tool_result")
	assert_that(parsed["request_id"]).is_equal("r1")
	assert_that(parsed["result"]["ok"]).is_true()


func test_build_interrupt_frame():
	var json_text := AgentSessionHelpers.build_interrupt_frame()
	var parsed = JSON.parse_string(json_text)
	assert_that(parsed["type"]).is_equal("interrupt")


func test_parse_server_frame_agent_text():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"agent_text","text":"hi"}')
	assert_that(parsed["type"]).is_equal("agent_text")
	assert_that(parsed["text"]).is_equal("hi")


func test_parse_server_frame_agent_text_done():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"agent_text_done"}')
	assert_that(parsed["type"]).is_equal("agent_text_done")


func test_parse_server_frame_tool_call():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"tool_call","request_id":"r1","name":"load_specimen","args":{"a":1},"executor":0}')
	assert_that(parsed["type"]).is_equal("tool_call")
	assert_that(parsed["request_id"]).is_equal("r1")
	assert_that(parsed["name"]).is_equal("load_specimen")
	assert_that(parsed["args"]["a"]).is_equal(1.0)
	assert_that(parsed["executor"]).is_equal(0)


func test_parse_server_frame_status():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"status","text":"thinking"}')
	assert_that(parsed["type"]).is_equal("status")
	assert_that(parsed["text"]).is_equal("thinking")


func test_parse_server_frame_error():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"error","message":"boom"}')
	assert_that(parsed["type"]).is_equal("error")
	assert_that(parsed["message"]).is_equal("boom")


func test_parse_server_frame_history():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"history","entries":[1,2],"client_id":3}')
	assert_that(parsed["type"]).is_equal("history")
	# Godot's JSON parser returns all numbers as float, even inside arrays;
	# entries contents are left untouched by parse_server_frame, so we cast
	# here to document that reality rather than pretend they're already int.
	assert_that(int(parsed["entries"][0])).is_equal(1)
	assert_that(int(parsed["entries"][1])).is_equal(2)
	assert_that(parsed["client_id"]).is_equal(3)


func test_parse_server_frame_turn_queued():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"turn_queued","position":2}')
	assert_that(parsed["type"]).is_equal("turn_queued")
	assert_that(parsed["position"]).is_equal(2)


func test_parse_server_frame_reserved_type_passthrough():
	var parsed := AgentSessionHelpers.parse_server_frame('{"type":"speaker_bound"}')
	assert_that(parsed["type"]).is_equal("speaker_bound")


func test_parse_server_frame_bad_json():
	var parsed := AgentSessionHelpers.parse_server_frame("not json")
	assert_that(parsed.has("error")).is_true()


func test_parse_server_frame_missing_type():
	var parsed := AgentSessionHelpers.parse_server_frame('{"text":"hi"}')
	assert_that(parsed.has("error")).is_true()


func test_parse_server_frame_not_a_dict():
	var parsed := AgentSessionHelpers.parse_server_frame('[1,2,3]')
	assert_that(parsed.has("error")).is_true()


func test_encode_binary_layout():
	var payload := PackedByteArray([1, 2, 3, 4, 5])
	var data := AgentSessionHelpers.encode_binary({"kind": "screenshot", "mime": "image/jpeg"}, payload)
	var header_len := data.decode_u32(0)
	var header_bytes := data.slice(4, 4 + header_len)
	var header = JSON.parse_string(header_bytes.get_string_from_utf8())
	assert_that(header["kind"]).is_equal("screenshot")
	assert_that(header["mime"]).is_equal("image/jpeg")
	var body := data.slice(4 + header_len, data.size())
	assert_that(body).is_equal(payload)


func test_encode_binary_roundtrip_via_binary_envelope():
	var payload := PackedByteArray([9, 8, 7])
	var data := AgentSessionHelpers.encode_binary({"kind": "screenshot"}, payload)
	var parsed := BinaryEnvelope.parse(data)
	assert_that(parsed.has("preamble")).is_true()
	assert_that(parsed["preamble"]["kind"]).is_equal("screenshot")
	assert_that(parsed["offset"]).is_equal(data.size() - payload.size())
