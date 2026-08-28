# Diagnostic: does AudioEffectCapture on a fresh bus receive mic frames,
# (a) alone and (b) while a second AudioStreamMicrophone player is active
# (simulating twovoip's always-on mic)? Run windowed (audio needs a device):
#   Godot_v4.6-stable_win64_console.exe --path . -s res://tools/mic_probe.gd
extends SceneTree

var _phase: int = 0
var _elapsed: float = 0.0
var _capture: AudioEffectCapture
var _probe_player: AudioStreamPlayer
var _rival_player: AudioStreamPlayer
var _samples: Array[int] = []


func _initialize() -> void:
	print("[probe] mix_rate=", AudioServer.get_mix_rate(), " input_device=", AudioServer.input_device)
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "ProbeBus")
	AudioServer.set_bus_mute(idx, true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(idx, _capture)

	_probe_player = AudioStreamPlayer.new()
	_probe_player.stream = AudioStreamMicrophone.new()
	_probe_player.bus = "ProbeBus"
	root.add_child(_probe_player)
	_probe_player.play()
	print("[probe] phase 1: capture alone")


func _process(delta: float) -> bool:
	_elapsed += delta
	_samples.append(_capture.get_frames_available())
	_capture.clear_buffer()

	if _phase == 0 and _elapsed > 3.0:
		var total1: int = 0
		for s: int in _samples:
			total1 += s
		print("[probe] phase 1 result: total frames over 3s = ", total1)
		_samples.clear()
		_elapsed = 0.0
		_phase = 1
		_rival_player = AudioStreamPlayer.new()
		_rival_player.stream = AudioStreamMicrophone.new()
		_rival_player.bus = "Master"
		_rival_player.volume_db = -80.0
		root.add_child(_rival_player)
		_rival_player.play()
		print("[probe] phase 2: capture with rival mic stream active")
	elif _phase == 1 and _elapsed > 3.0:
		var total2: int = 0
		for s: int in _samples:
			total2 += s
		print("[probe] phase 2 result: total frames over 3s = ", total2)
		quit()
	return false
