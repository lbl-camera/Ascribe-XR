extends "res://scripts/mesh_specimen.gd"

var mqtt_client = null

var specimens = []

func _enter_tree() -> void:
	super()
	mqtt_client = get_tree().get_root().find_child("MQTT", true, false)
	mqtt_client.subscribe("python/processing_responses")
	mqtt_client.subscribe("python/specimen_responses")
	mqtt_client.connect("received_message", _on_mqtt_message_received)

	var specimen_list:ItemList = ui_instance.get_node('%SpecimenList')
	specimen_list.item_selected.connect(specimen_selected)

	ui_instance.get_node("%FileDialogLayer").hide()

	send_specimens_request()
	
func specimen_selected(index:int):
	ui_instance.get_node("%SpecimenLayer").hide()
	send_processing_request(specimens[index])
	
func send_specimens_request():
	mqtt_client.publish("godot/specimen_requests", JSON.stringify(null))

func send_processing_request(function_name, args=null, kwargs=null):
	if args == null:
		args = []

	if kwargs == null:
		kwargs = {}

	var request_data = {
		'function_name': function_name,
		'args': args,
		'kwargs': kwargs
	}
	mqtt_client.publish("godot/processing_requests", JSON.stringify(request_data))

var mesh_received = false

func _on_mqtt_message_received(_topic, message):
	match _topic:
		"python/processing_responses":
			if mesh_received == true:
				return

			if multiplayer.get_unique_id() != 1:
				return

			var result_data = JSON.parse_string(message)

			#var max_idx = 0
			#for i in idxs:
				#if i >= verts.size():
					#push_error("Bad index: " + str(i))
				#max_idx = max(max_idx, i)
			#print("Max index:", max_idx, "Vertex count:", verts.size())

			set_and_send_mesh(result_data)
			#send_mesh(verts, idxs)
			mesh_received = true
		"python/specimen_responses":
			specimens = JSON.parse_string(message)['names']
			print("new specimens: ", specimens)
			generate_specimen_menu(specimens)
			
func generate_specimen_menu(specimens:Array):
	var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
	specimen_list.clear()
	for specimen_name in specimens:
		specimen_list.add_item(specimen_name)
