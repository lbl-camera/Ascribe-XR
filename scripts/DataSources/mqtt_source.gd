## MQTT-based data source.
## Sends a request to Python and receives mesh data back.
class_name MQTTSource
extends DataSource

var _mqtt_client: Node
var _request_topic: String
var _response_topic: String
var _request_payload: Dictionary
var _is_waiting: bool = false


func _init(mqtt: Node = null, request_topic: String = "godot/processing_requests",
		response_topic: String = "python/processing_responses") -> void:
	_mqtt_client = mqtt
	_request_topic = request_topic
	_response_topic = response_topic


func setup(mqtt: Node) -> void:
	_mqtt_client = mqtt
	_mqtt_client.subscribe(_response_topic)
	_mqtt_client.received_message.connect(_on_message)


func set_request(payload: Dictionary) -> void:
	_request_payload = payload


func is_available() -> bool:
	return _mqtt_client != null


func fetch() -> void:
	if not is_available():
		source_error.emit("MQTT not connected")
		return
	_is_waiting = true
	var json := JSON.stringify(_request_payload)
	_mqtt_client.publish(_request_topic, json)


func cancel() -> void:
	_is_waiting = false


func _on_message(topic: String, message: String) -> void:
	if not _is_waiting or topic != _response_topic:
		return
	_is_waiting = false
	var parsed = JSON.parse_string(message)
	if parsed == null:
		source_error.emit("Invalid JSON response from MQTT")
		return
	data_available.emit(parsed)
