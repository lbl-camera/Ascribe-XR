extends XROrigin3D

func _on_left_hand_controller_button_pressed(name: String) -> void:
	pass
	var event = InputEventAction.new()
	if name == 'menu_button' or name == 'by_button':
		event.action = "ui_menu"
	event.pressed = true
	if event.action:
		Input.parse_input_event(event)
