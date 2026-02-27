## Dynamic mesh specimen — loads meshes from Python via MQTT.
## Uses MQTTSource for the data pipeline.
extends MeshSpecimen

var _mqtt_source: MQTTSource
var _mqtt_client: Node
var specimens: Array = []
var mesh_received: bool = false


func _enter_tree() -> void:
	super()

	_mqtt_client = get_tree().get_root().find_child("MQTT", true, false)
	if _mqtt_client == null:
		push_error("DynamicMeshSpecimen: MQTT client not found")
		return

	# Set up MQTT source for processing requests
	_mqtt_source = MQTTSource.new()
	_mqtt_source.setup(_mqtt_client)
	_mqtt_source.data_available.connect(_on_mqtt_data)
	_mqtt_source.source_error.connect(func(e): push_error("MQTT: " + e))

	# Also subscribe to specimen list responses
	_mqtt_client.subscribe("python/specimen_responses")
	_mqtt_client.received_message.connect(_on_raw_mqtt_message)

	if ui_instance:
		var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
		specimen_list.item_selected.connect(_on_specimen_selected)
		ui_instance.get_node("%FileDialogLayer").hide()

	_request_specimen_list()


func _request_specimen_list() -> void:
	_mqtt_client.publish("godot/specimen_requests", JSON.stringify(null))


func _on_specimen_selected(index: int) -> void:
	if ui_instance:
		ui_instance.get_node("%SpecimenLayer").hide()
	mesh_received = false
	_mqtt_source.set_request({
		"function_name": specimens[index],
		"args": [],
		"kwargs": {}
	})
	_mqtt_source.fetch()


func _on_mqtt_data(result_data: Variant) -> void:
	if mesh_received:
		return
	if multiplayer.get_unique_id() != 1:
		return

	mesh_received = true
	var data = MeshData.new()
	data.set_from_dict(result_data)
	_mesh_data = data
	_set_and_send_mesh(data)


## Handle specimen list responses (separate from the MQTTSource pipeline).
func _on_raw_mqtt_message(topic: String, message: String) -> void:
	if topic == "python/specimen_responses":
		var parsed = JSON.parse_string(message)
		if parsed and parsed.has("names"):
			specimens = parsed["names"]
			_generate_specimen_menu(specimens)


func _generate_specimen_menu(specimen_names: Array) -> void:
	if ui_instance == null:
		return
	var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
	specimen_list.clear()
	for specimen_name in specimen_names:
		specimen_list.add_item(specimen_name)
