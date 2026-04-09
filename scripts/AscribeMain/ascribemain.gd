extends Node3D

@onready var NetworkGateway = $NetworkGateway


func _ready():
	if OS.has_feature("QUEST"):
		if Config.QUESTstartupprotocol == "webrtc":
			NetworkGateway.initialstatemqttwebrtc(NetworkGateway.NETWORK_OPTIONS_MQTT_WEBRTC.AS_NECESSARY, Config.webrtcroomname, Config.webrtcbroker)
		elif Config.QUESTstartupprotocol == "enet":
			NetworkGateway.initialstatenormal(NetworkGateway.NETWORK_PROTOCOL.ENET, NetworkGateway.NETWORK_OPTIONS.AS_CLIENT)
	else:
		if Config.PCstartupprotocol == "webrtc":
			NetworkGateway.initialstatemqttwebrtc(NetworkGateway.NETWORK_OPTIONS_MQTT_WEBRTC.AS_NECESSARY, Config.webrtcroomname, Config.webrtcbroker)
		elif Config.PCstartupprotocol == "enet":
			NetworkGateway.initialstatenormal(NetworkGateway.NETWORK_PROTOCOL.ENET, NetworkGateway.NETWORK_OPTIONS.AS_SERVER)

	$XROrigin3D/RightHandController.button_pressed.connect(vr_right_button_pressed)
	$XROrigin3D/RightHandController.button_released.connect(vr_right_button_release)
	$XROrigin3D/LeftHandController.button_pressed.connect(vr_left_button_pressed)

	$XROrigin3D/PlayerBody.default_physics.move_drag = 45
	NetworkGateway.set_process_input(false)
	if Config.webrtcroomname:
		NetworkGateway.MQTTsignalling.Roomnametext.text = Config.webrtcroomname
		NetworkGateway.simple_webrtc_connect(Config.webrtcroomname)


func _toggle_network_gateway_menu():
	if MenuManager.has_active_menu("network"):
		MenuManager.close_menu("network")
	else:
		MenuManager.show_menu(NetworkGateway, {
			"slot": "network",
			"screen_size": Vector2(3, 2),
			"viewport_size": Vector2(690, 400),
			"preserve_content": true,
		})


func vr_right_button_pressed(button: String):
	print("vr right button pressed ", button)
	if button == "by_button":
		_toggle_network_gateway_menu()


func vr_right_button_release(button: String):
	pass


func vr_left_button_pressed(button: String):
	print("vr left button pressd ", button)
	if button == "ax_button":
		pass
	if button == "by_button":
		print("Publishing Right hand XR transforms to mqtt hand/pos")


func _input(event):
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_M and event.pressed:
			_toggle_network_gateway_menu()
		if event.keycode == KEY_F and event.pressed:
			vr_left_button_pressed("by_button")
		if event.keycode == KEY_G and event.pressed:
			NetworkGateway.DoppelgangerPanel.get_node("hbox/VBox_enable/DoppelgangerEnable").button_pressed = not NetworkGateway.DoppelgangerPanel.get_node("hbox/VBox_enable/DoppelgangerEnable").button_pressed

		if (event.keycode == KEY_4) and event.pressed:
			NetworkGateway.PlayerConnections.LocalPlayer.projectedhands = not NetworkGateway.get_node("PlayerConnections").LocalPlayer.projectedhands

		if (event.keycode == KEY_C) and event.pressed:
			_on_interactable_area_button_button_pressed(null)


func _physics_process(delta):
	var lowestfloorheight = -30
	if $XROrigin3D.transform.origin.y < lowestfloorheight:
		$XROrigin3D.transform.origin = Vector3(0, 2, 0)


func _process(delta):
	pass


func _on_interactable_area_button_button_pressed(button):
	if NetworkGateway.is_disconnected():
		NetworkGateway.simple_webrtc_connect(Config.webrtcroomname)
	if button:
		button.get_node("Label3D").text = "X"
