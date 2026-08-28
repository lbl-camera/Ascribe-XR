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


func start_capture() -> void:
	if _capturing:
		return
	_ensure_bus()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS_NAME
		add_child(_player)
	_player.play()
	_capturing = true


func stop_capture() -> void:
	_capturing = false
	if _player != null:
		_player.stop()


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
	if not _capturing or _capture == null:
		return
	var available := _capture.get_frames_available()
	while available > 0:
		var chunk_frames: int = mini(available, MAX_FRAMES_PER_SEND)
		var frames := _capture.get_buffer(chunk_frames)
		var pcm := AgentSessionHelpers.frames_to_pcm16_mono(frames)
		AgentSession.send_audio(pcm, int(AudioServer.get_mix_rate()))
		available -= chunk_frames
