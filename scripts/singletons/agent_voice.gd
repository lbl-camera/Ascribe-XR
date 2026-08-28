## AgentVoice -- plays server->client TTS audio frames from AgentSession
## through an AudioStreamGenerator.
##
## Autoload (no class_name: colliding with the AgentVoice global class name
## caused an autoload/global-class registration conflict). Static helpers
## remain callable via `preload("res://scripts/singletons/agent_voice.gd")`.
extends Node

## Length of the AudioStreamGenerator ring buffer, in seconds. One Kokoro
## sentence arrives as a single binary frame far larger than this buffer
## (24k-120k frames vs ~12k), so payloads are queued in `_pending` and drained
## into the playback a bufferful at a time from `_process`.
const BUFFER_LENGTH_S := 0.5

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _is_playing_agent_audio: bool = false
## Frames received but not yet pushed into the generator's ring buffer.
var _pending := PackedVector2Array()

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


## Split `pending` at the generator's currently available frame count.
## Returns [to_push, remaining] -- pure so the drain math is unit testable.
static func take_drainable(pending: PackedVector2Array, available: int) -> Array:
	if available <= 0 or pending.is_empty():
		return [PackedVector2Array(), pending]
	if available >= pending.size():
		return [pending, PackedVector2Array()]
	return [pending.slice(0, available), pending.slice(available)]


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	AgentSession.tts_audio.connect(_on_tts_audio)
	AgentSession.agent_audio_ended.connect(_on_agent_audio_ended)
	AgentSession.disconnected.connect(_on_agent_audio_ended)


func _on_tts_audio(header: Dictionary, payload: PackedByteArray) -> void:
	if _playback == null:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = float(header.get("rate", 24000))
		generator.buffer_length = BUFFER_LENGTH_S
		_player.stream = generator
		_player.play()
		_playback = _player.get_stream_playback()

	_pending.append_array(pcm16_to_frames(payload))
	_is_playing_agent_audio = true
	_drain_pending()


func _process(_delta: float) -> void:
	_drain_pending()


func _drain_pending() -> void:
	if _playback == null or _pending.is_empty():
		return
	var split := take_drainable(_pending, _playback.get_frames_available())
	var to_push: PackedVector2Array = split[0]
	_pending = split[1]
	if not to_push.is_empty():
		_playback.push_buffer(to_push)


func _on_agent_audio_ended() -> void:
	_player.stop()
	_playback = null
	_pending = PackedVector2Array()
	_is_playing_agent_audio = false
