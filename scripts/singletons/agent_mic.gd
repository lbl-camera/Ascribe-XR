## AgentMic -- dedicated microphone capture bus that streams PCM16 audio to
## the agent conversation WebSocket while the local speaker floor is bound.
##
## Uses its own "AgentMicBus" + AudioEffectCapture + AudioStreamMicrophone,
## entirely separate from the MicrophoneBus / AudioEffectOpusChunked used by
## twovoip voice chat (see two_voip_mic.gd) -- never touch that bus or call
## drop_chunk() on its effect.
extends Node

const BUS_NAME := "AgentMicBus"
const CAPTURE_BUFFER_SECONDS := 0.5
const MAX_FRAMES_PER_SEND := 4096

var _bus_index: int = -1
var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _capturing: bool = false
var _frames_sent: int = 0


## Open the mic device without sending anything. Windows streams zeros for a
## second or two while the capture device warms up; calling this when the
## agent panel opens means the first Talk press hears the user immediately.
func prewarm() -> void:
	_ensure_bus()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS_NAME
		add_child(_player)
	if not _player.playing:
		_player.play()
		print("[AgentMic] prewarmed (device opening)")


func start_capture() -> void:
	if _capturing:
		return
	prewarm()
	_capture.clear_buffer()  # drop warm-up/idle frames, start the utterance clean
	_capturing = true
	_frames_sent = 0
	print("[AgentMic] capture started (bus=%d, playing=%s, mix_rate=%d, input_device=%s)" % [
		_bus_index, str(_player.playing), int(AudioServer.get_mix_rate()), AudioServer.input_device])


func stop_capture() -> void:
	# Keep the device open (warm) between utterances; _process drops idle
	# frames while not capturing so the next Talk press starts instantly.
	_capturing = false


func _ensure_bus() -> void:
	if _bus_index != -1:
		return
	_bus_index = AudioServer.bus_count
	AudioServer.add_bus(_bus_index)
	AudioServer.set_bus_name(_bus_index, BUS_NAME)
	AudioServer.set_bus_mute(_bus_index, true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = CAPTURE_BUFFER_SECONDS
	AudioServer.add_bus_effect(_bus_index, _capture)


func _process(_delta: float) -> void:
	if _capture == null:
		return
	if not _capturing:
		# Device stays warm; discard idle frames so they never leak into
		# the next utterance and the ring buffer never overflows.
		if _capture.get_frames_available() > 0:
			_capture.clear_buffer()
		return
	var available := _capture.get_frames_available()
	while available > 0:
		var chunk_frames: int = mini(available, MAX_FRAMES_PER_SEND)
		var frames := _capture.get_buffer(chunk_frames)
		var pcm := AgentSessionHelpers.frames_to_pcm16_mono(frames)
		AgentSession.send_audio(pcm, int(AudioServer.get_mix_rate()))
		if _frames_sent == 0:
			print("[AgentMic] first chunk sent (%d frames, %d bytes)" % [chunk_frames, pcm.size()])
		_frames_sent += chunk_frames
		available -= chunk_frames
