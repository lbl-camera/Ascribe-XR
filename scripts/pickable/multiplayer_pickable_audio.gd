extends XRToolsPickableAudio

# Called when this object is picked up
func _on_picked_up(_pickable) -> void:
	volume_db = 0
	if playing:
		stop_multiplayer.rpc()
	play_multiplayer.rpc(pickable_audio_type.grab_sound)

func _on_body_entered(_body):
	if playing:
		stop_multiplayer.rpc()
	if _pickable.is_picked_up():
		play_multiplayer.rpc(pickable_audio_type.hit_sound)
	else:
		play_multiplayer.rpc(pickable_audio_type.drop_sound)

	
@rpc("any_peer", "call_local", "reliable")
func play_multiplayer(sound):
	stream = sound
	play()

@rpc("any_peer", "call_local", "reliable")
func stop_multiplayer():
	stop()
