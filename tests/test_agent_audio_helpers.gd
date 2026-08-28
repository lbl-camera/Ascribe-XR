extends GdUnitTestSuite


func test_audio_header():
	assert_that(AgentSessionHelpers.audio_header(44100)).is_equal({
		"kind": "audio", "rate": 44100, "format": "s16le", "channels": 1
	})


func test_frames_to_pcm16_mono_positive_full_scale():
	var frames := PackedVector2Array([Vector2(1.0, 0.0)])
	var pcm := AgentSessionHelpers.frames_to_pcm16_mono(frames)
	assert_that(pcm.size()).is_equal(2)
	var value := pcm.decode_s16(0)
	assert_that(value).is_between(16382, 16384)


func test_frames_to_pcm16_mono_negative_clamped():
	var frames := PackedVector2Array([Vector2(-1.0, -1.0)])
	var pcm := AgentSessionHelpers.frames_to_pcm16_mono(frames)
	assert_that(pcm.size()).is_equal(2)
	assert_that(pcm.decode_s16(0)).is_equal(-32768)


func test_frames_to_pcm16_mono_empty():
	var frames := PackedVector2Array()
	var pcm := AgentSessionHelpers.frames_to_pcm16_mono(frames)
	assert_that(pcm.size()).is_equal(0)


func test_frames_to_pcm16_mono_length_is_two_bytes_per_frame():
	var frames := PackedVector2Array([Vector2(0.1, 0.2), Vector2(-0.3, 0.4), Vector2(0.0, 0.0)])
	var pcm := AgentSessionHelpers.frames_to_pcm16_mono(frames)
	assert_that(pcm.size()).is_equal(6)


func test_build_bind_frame():
	var json_text := AgentSessionHelpers.build_bind_frame()
	var parsed = JSON.parse_string(json_text)
	assert_that(parsed["type"]).is_equal("bind")


func test_build_unbind_frame():
	var json_text := AgentSessionHelpers.build_unbind_frame()
	var parsed = JSON.parse_string(json_text)
	assert_that(parsed["type"]).is_equal("unbind")
