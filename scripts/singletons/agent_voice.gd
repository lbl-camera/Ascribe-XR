## AgentVoice -- plays server->client TTS audio frames from AgentSession
## through an AudioStreamGenerator.
##
## Autoload (no class_name: colliding with the AgentVoice global class name
## caused an autoload/global-class registration conflict). Static helpers
## remain callable via `preload("res://scripts/singletons/agent_voice.gd")`.
extends Node

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _is_playing_agent_audio: bool = false

var is_playing_agent_audio: bool:
	get:
		return _is_playing_agent_audio


## Convert PCM16 LE mono bytes into stereo frames (Vector2(v, v)) scaled to
## [-1, 1], as required by AudioStreamGeneratorPlayback.push_buffer().
static func pcm16_to_frames(pcm: PackedByteArray) -> PackedVector2Array:
	var frame_count: int = pcm.size() / 2
	var frames := PackedVector2Array()
	frames.resize(frame_count)
	for i in frame_count:
		var sample: int = pcm.decode_s16(i * 2)
		var scale: float = 32768.0 if sample < 0 else 32767.0
		var v: float = float(sample) / scale
		frames[i] = Vector2(v, v)
	return frames


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	AgentSession.tts_audio.connect(_on_tts_audio)
	AgentSession.agent_audio_ended.connect(_on_agent_audio_ended)
	AgentSession.disconnected.connect(_on_agent_audio_ended)
	AgentSession.error_received.connect(_on_error_received)


func _on_tts_audio(header: Dictionary, payload: PackedByteArray) -> void:
	if _playback == null:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = float(header.get("rate", 24000))
		generator.buffer_length = 0.5
		_player.stream = generator
		_player.play()
		_playback = _player.get_stream_playback()

	var frames := pcm16_to_frames(payload)
	var available: int = _playback.get_frames_available()
	if available < frames.size():
		push_warning("AgentVoice: dropping %d frames (buffer full)" % (frames.size() - available))
		if available > 0:
			_playback.push_buffer(frames.slice(0, available))
	else:
		_playback.push_buffer(frames)
	_is_playing_agent_audio = true


func _on_agent_audio_ended() -> void:
	_player.stop()
	_playback = null
	_is_playing_agent_audio = false


func _on_error_received(_message: String) -> void:
	_on_agent_audio_ended()
