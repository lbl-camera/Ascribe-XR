extends GdUnitTestSuite


func _build_envelope(preamble_json: String, body: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var preamble_bytes := preamble_json.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, preamble_bytes.size())
	out.append_array(preamble_bytes)
	out.append_array(body)
	return out


func test_media_type_constant():
	assert_that(BinaryEnvelope.MEDIA_TYPE).is_equal("application/x-ascribe-envelope-v1")


func test_parse_valid_envelope():
	var env := _build_envelope('{"type":"mesh","vertex_count":0,"vertex_dtype":"float32","index_count":0,"index_dtype":"uint32","normal_count":0,"normal_dtype":"float32"}')
	var parsed = BinaryEnvelope.parse(env)
	assert_that(parsed.has("preamble")).is_true()
	assert_that(parsed["preamble"]["type"]).is_equal("mesh")
	assert_that(parsed["offset"]).is_equal(env.size())


func test_parse_with_trailing_body():
	var body := PackedByteArray([1, 2, 3, 4, 5])
	var env := _build_envelope('{"type":"volume","shape":[1,1,1],"dtype":"uint8","spacing":[1,1,1],"origin":[0,0,0]}', body)
	var parsed = BinaryEnvelope.parse(env)
	assert_that(parsed["preamble"]["type"]).is_equal("volume")
	assert_that(parsed["offset"]).is_equal(env.size() - body.size())


func test_parse_truncated_length_prefix():
	var parsed = BinaryEnvelope.parse(PackedByteArray([0x01, 0x00]))
	assert_that(parsed.has("error")).is_true()
	assert_that(parsed["error"]).contains("length prefix")


func test_parse_truncated_preamble():
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, 100)
	out.append(0x7B)
	var parsed = BinaryEnvelope.parse(out)
	assert_that(parsed.has("error")).is_true()
	assert_that(parsed["error"]).contains("preamble")


func test_parse_invalid_json():
	var env := _build_envelope("not json")
	var parsed = BinaryEnvelope.parse(env)
	assert_that(parsed.has("error")).is_true()
	assert_that(parsed["error"]).contains("JSON")
