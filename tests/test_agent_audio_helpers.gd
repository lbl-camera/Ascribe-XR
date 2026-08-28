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


const AgentVoiceScript = preload("res://scripts/singletons/agent_voice.gd")


func test_decode_binary_round_trips_with_encode_binary():
	var header := {"kind": "tts", "rate": 24000, "format": "s16le", "channels": 1, "seq": 3}
	var payload := PackedByteArray([1, 2, 3, 4])
	var frame := AgentSessionHelpers.encode_binary(header, payload)
	var decoded := AgentSessionHelpers.decode_binary(frame)
	assert_that(decoded.has("error")).is_false()
	assert_that(decoded["header"]).is_equal(JSON.parse_string(JSON.stringify(header)))
	assert_that(decoded["payload"]).is_equal(payload)


func test_decode_binary_too_short_for_header_length():
	var data := PackedByteArray([1, 2, 3])
	var decoded := AgentSessionHelpers.decode_binary(data)
	assert_that(decoded.has("error")).is_true()


func test_decode_binary_truncated_header():
	var data := PackedByteArray()
	data.resize(4)
	data.encode_u32(0, 100)
	var decoded := AgentSessionHelpers.decode_binary(data)
	assert_that(decoded.has("error")).is_true()


func test_pcm16_to_frames_single_sample():
	var pcm := PackedByteArray()
	pcm.resize(2)
	pcm.encode_s16(0, 1000)
	var frames := AgentVoiceScript.pcm16_to_frames(pcm)
	assert_that(frames.size()).is_equal(1)


func test_pcm16_to_frames_positive_full_scale():
	var pcm := PackedByteArray()
	pcm.resize(2)
	pcm.encode_s16(0, 32767)
	var frames := AgentVoiceScript.pcm16_to_frames(pcm)
	assert_that(frames[0].x).is_between(0.999, 1.0001)
	assert_that(frames[0].y).is_between(0.999, 1.0001)


func test_pcm16_to_frames_negative_full_scale():
	var pcm := PackedByteArray()
	pcm.resize(2)
	pcm.encode_s16(0, -32768)
	var frames := AgentVoiceScript.pcm16_to_frames(pcm)
	assert_that(frames[0].x).is_equal(-1.0)
	assert_that(frames[0].y).is_equal(-1.0)


# ---------------------------------------------------------------------------
# take_drainable: the pending-queue drain math (one Kokoro sentence is far
# larger than the generator's ~0.5 s ring buffer, so it drains over frames).
# ---------------------------------------------------------------------------

static func _silence(n: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(n)
	return frames


func test_take_drainable_splits_large_payload_at_available():
	# 2 s @ 24 kHz pending, 0.5 s (12000 frames) of ring buffer available.
	var split := AgentVoiceScript.take_drainable(_silence(48000), 12000)
	var to_push: PackedVector2Array = split[0]
	var remaining: PackedVector2Array = split[1]
	assert_that(to_push.size()).is_equal(12000)
	assert_that(remaining.size()).is_equal(36000)


func test_take_drainable_repeated_calls_empty_the_queue():
	var pending := _silence(48000)
	var pushed_total: int = 0
	for _i in 4:
		var split := AgentVoiceScript.take_drainable(pending, 12000)
		var to_push: PackedVector2Array = split[0]
		pushed_total += to_push.size()
		pending = split[1]
	assert_that(pushed_total).is_equal(48000)
	assert_that(pending.size()).is_equal(0)


func test_take_drainable_pushes_all_when_available_exceeds_pending():
	var split := AgentVoiceScript.take_drainable(_silence(100), 12000)
	var to_push: PackedVector2Array = split[0]
	var remaining: PackedVector2Array = split[1]
	assert_that(to_push.size()).is_equal(100)
	assert_that(remaining.size()).is_equal(0)


func test_take_drainable_no_room_keeps_everything_pending():
	var split := AgentVoiceScript.take_drainable(_silence(48000), 0)
	var to_push: PackedVector2Array = split[0]
	var remaining: PackedVector2Array = split[1]
	assert_that(to_push.size()).is_equal(0)
	assert_that(remaining.size()).is_equal(48000)


func test_take_drainable_empty_pending():
	var split := AgentVoiceScript.take_drainable(PackedVector2Array(), 12000)
	var to_push: PackedVector2Array = split[0]
	assert_that(to_push.size()).is_equal(0)


func test_agent_audio_ended_clears_pending():
	var voice: Node = AgentVoiceScript.new()
	voice._pending = _silence(48000)
	voice._is_playing_agent_audio = true
	voice._player = AudioStreamPlayer.new()
	auto_free(voice)
	auto_free(voice._player)
	voice._on_agent_audio_ended()
	assert_that(voice._pending.size()).is_equal(0)
	assert_that(voice._is_playing_agent_audio).is_false()


# ---------------------------------------------------------------------------
# should_stop_draining: the normal-end drain-to-completion decision.
# ---------------------------------------------------------------------------


func test_should_stop_draining_false_while_pending_nonempty():
	assert_that(AgentVoiceScript.should_stop_draining(false, 12000, 24000)).is_false()


func test_should_stop_draining_false_while_ring_buffer_not_drained():
	# Pending empty, but the ring buffer still has unplayed frames queued
	# (frames_available well below the buffer's full capacity).
	assert_that(AgentVoiceScript.should_stop_draining(true, 1000, 24000)).is_false()


func test_should_stop_draining_true_once_buffer_has_caught_up():
	# Pending empty and frames_available has climbed back to the buffer's
	# full capacity (0.5 s @ 24 kHz) -- nothing left queued or playing.
	assert_that(AgentVoiceScript.should_stop_draining(true, 12000, 24000)).is_true()


func test_agent_audio_ended_interrupted_hard_stops_even_with_playback():
	var voice: Node = AgentVoiceScript.new()
	voice._pending = _silence(48000)
	voice._is_playing_agent_audio = true
	voice._draining_to_end = false
	voice._player = AudioStreamPlayer.new()
	auto_free(voice)
	auto_free(voice._player)
	voice._on_agent_audio_ended(true)
	assert_that(voice._pending.size()).is_equal(0)
	assert_that(voice._is_playing_agent_audio).is_false()
	assert_that(voice._draining_to_end).is_false()


func test_agent_audio_ended_not_interrupted_without_playback_stops_immediately():
	# No tts_audio ever arrived (_playback still null) -- nothing to drain.
	var voice: Node = AgentVoiceScript.new()
	voice._is_playing_agent_audio = true
	voice._player = AudioStreamPlayer.new()
	auto_free(voice)
	auto_free(voice._player)
	voice._on_agent_audio_ended(false)
	assert_that(voice._is_playing_agent_audio).is_false()
	assert_that(voice._draining_to_end).is_false()
