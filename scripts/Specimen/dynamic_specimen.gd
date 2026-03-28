## Dynamic specimen — loads data from Ascribe-Link HTTP API.
## Handles multiple data types (mesh, volume, etc.) based on the response 'type' field.
## Uses HTTPSource for the data pipeline and AscribeLinkClient for catalog.
class_name DynamicSpecimen
extends Node3D

signal data_loaded(data_type: String)
signal load_error(error: String)

var _http_source: HTTPSource
var _link_client: AscribeLinkClient
var _server_url: String

## Array of function info dicts from /api/processing/functions
var functions: Array = []

## Currently loaded specimen instance
var _current_specimen: Node3D = null

## Scenes for different data types
const MESH_SPECIMEN_SCENE = preload("res://specimens/dynamic_mesh_specimen.tscn")
const VOLUME_SPECIMEN_SCENE = preload("res://specimens/volume_specimen.tscn")


func _ready() -> void:
	_server_url = Config.ascribe_link_url
	
	# Initialize HTTP client for catalog operations
	_link_client = AscribeLinkClient.new(_server_url)
	_link_client.setup(self)
	_link_client.functions_loaded.connect(_on_functions_loaded)
	_link_client.request_error.connect(func(e): _emit_error("AscribeLink: " + e))
	
	# Initialize HTTP source for processing requests
	_http_source = HTTPSource.new(_server_url)
	_http_source.setup(self)
	_http_source.data_available.connect(_on_http_data)
	_http_source.source_error.connect(func(e): _emit_error("HTTPSource: " + e))
	
	# Fetch available functions
	_link_client.fetch_functions()


func _emit_error(msg: String) -> void:
	push_error(msg)
	load_error.emit(msg)


func _on_functions_loaded(funcs: Array) -> void:
	functions = funcs
	print("DynamicSpecimen: Loaded %d functions" % funcs.size())


## Invoke a processing function by name.
func invoke_function(function_name: String, args: Array = [], kwargs: Dictionary = {}) -> void:
	_http_source.set_request({
		"function_name": function_name,
		"args": args,
		"kwargs": kwargs,
	})
	_http_source.fetch()


## Invoke the AI generation function with a prompt.
func generate_with_ai(prompt: String, file_path: String = "") -> void:
	var kwargs = {"prompt": prompt}
	if not file_path.is_empty():
		kwargs["file_path"] = file_path
	invoke_function("ai_generate", [], kwargs)


func _on_http_data(result_data: Variant) -> void:
	if not result_data is Dictionary:
		_emit_error("Invalid response: expected Dictionary")
		return
	
	var data_type: String = result_data.get("type", "mesh")
	print("DynamicSpecimen: Received %s data" % data_type)
	
	match data_type:
		"mesh":
			_handle_mesh_result(result_data)
		"volume":
			_handle_volume_result(result_data)
		"point_cloud":
			_handle_point_cloud_result(result_data)
		"image":
			_handle_image_result(result_data)
		_:
			_emit_error("Unknown data type: %s" % data_type)


func _handle_mesh_result(data: Dictionary) -> void:
	var mesh_data = MeshData.new()
	mesh_data.set_from_dict(data)
	
	if not mesh_data.is_valid():
		_emit_error("Invalid mesh data")
		return
	
	# For now, emit signal with type — the scene can handle instantiation
	data_loaded.emit("mesh")
	
	# Store for retrieval
	set_meta("last_mesh_data", mesh_data)


func _handle_volume_result(data: Dictionary) -> void:
	var volume_data = VolumetricData.new()
	volume_data.set_from_dict(data)
	
	if not volume_data.is_valid():
		_emit_error("Invalid volume data")
		return
	
	data_loaded.emit("volume")
	set_meta("last_volume_data", volume_data)


func _handle_point_cloud_result(data: Dictionary) -> void:
	# Point cloud support - store for future use
	data_loaded.emit("point_cloud")
	set_meta("last_point_cloud_data", data)


func _handle_image_result(data: Dictionary) -> void:
	# Image support - store for future use
	data_loaded.emit("image")
	set_meta("last_image_data", data)


## Get the last loaded mesh data.
func get_mesh_data() -> MeshData:
	return get_meta("last_mesh_data", null)


## Get the last loaded volume data.
func get_volume_data() -> VolumetricData:
	return get_meta("last_volume_data", null)
