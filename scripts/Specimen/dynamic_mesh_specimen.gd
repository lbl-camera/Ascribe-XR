## Dynamic mesh specimen — loads meshes from Python via Ascribe-Link HTTP API.
## Uses HTTPSource for the data pipeline and AscribeLinkClient for catalog.
## Can also load pre-specified specimen data via data_url (set before _enter_tree).
extends MeshSpecimen

var _http_source: HTTPSource
var _link_client: AscribeLinkClient
var _server_url: String

var _room_id: String = "ascribe"
var _active_job_id: String = ""
var _message_log: Array[String] = []
const MESSAGE_LOG_CAP := 50

## Array of function info dicts from /api/processing/functions
var functions: Array = []
## Array of specimen info dicts from /api/specimens/
var specimens: Array = []

var mesh_received: bool = false

## URL to directly fetch specimen data (STL, etc.) — set this before adding to tree.
## When set, the specimen loads this URL immediately instead of showing the menu.
@export var data_url: String = ""

## Display name for the specimen (set from menu metadata)
@export var remote_display_name: String = ""

## Story text for the specimen (set from menu metadata)
@export var remote_story_text: Array = []


func set_data_url(url: String) -> void:
	data_url = url


func _enter_tree() -> void:
	super()

	# Get server URL from config
	_server_url = Config.ascribe_link_url

	# Initialize HTTP client for catalog operations
	_link_client = AscribeLinkClient.new(_server_url)
	_link_client.setup(self)
	_link_client.functions_loaded.connect(_on_functions_loaded)
	_link_client.specimens_loaded.connect(_on_specimens_loaded)
	_link_client.request_error.connect(func(e): push_error("AscribeLink: " + e))
	_link_client.job_progress.connect(_on_job_progress)
	_link_client.job_complete.connect(_on_job_complete)
	_link_client.job_error.connect(_on_job_error)
	multiplayer.peer_connected.connect(_on_peer_connected)

	# Initialize HTTP source for mesh processing requests
	_http_source = HTTPSource.new(_server_url)
	_http_source.setup(self)
	_http_source.data_available.connect(_on_http_data)
	_http_source.source_error.connect(func(e): push_error("HTTPSource: " + e))

	if ui_instance:
		var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
		specimen_list.item_selected.connect(_on_specimen_selected)
		ui_instance.get_node("%FileDialogLayer").hide()

	# If data_url is set, load directly instead of showing menus
	if data_url and not data_url.is_empty():
		_load_from_data_url()
	else:
		# Fetch both specimens and functions from the server
		_link_client.fetch_functions()
		_link_client.fetch_specimens()


## Set the Ascribe-Link server URL (call before _enter_tree or use set_server_url).
func set_server_url(url: String) -> void:
	_server_url = url
	if _link_client:
		_link_client = AscribeLinkClient.new(url)
		_link_client.setup(self)
		_link_client.functions_loaded.connect(_on_functions_loaded)
		_link_client.specimens_loaded.connect(_on_specimens_loaded)
		_link_client.request_error.connect(func(e): push_error("AscribeLink: " + e))
		_link_client.job_progress.connect(_on_job_progress)
		_link_client.job_complete.connect(_on_job_complete)
		_link_client.job_error.connect(_on_job_error)
	if _http_source:
		_http_source = HTTPSource.new(url)
		_http_source.setup(self)
		_http_source.data_available.connect(_on_http_data)
		_http_source.source_error.connect(func(e): push_error("HTTPSource: " + e))


func _on_functions_loaded(funcs: Array) -> void:
	functions = funcs
	# Functions are processing functions (sphere, etc.) — populate menu
	var names: Array = []
	for f in funcs:
		names.append(f.get("name", "unknown"))
	_generate_specimen_menu(names)


func _on_specimens_loaded(specs: Array) -> void:
	specimens = specs
	# Curated specimens — could add to a separate menu or combine with functions
	# For now, we prioritize functions (processing) over curated specimens


func _on_specimen_selected(index: int) -> void:
	if ui_instance:
		ui_instance.get_node("%SpecimenLayer").hide()
	mesh_received = false

	if index >= functions.size():
		push_error("Invalid function index: %d" % index)
		return

	var function_name = functions[index].get("name", "")
	_load_dynamic_specimen(function_name, {})


func _on_http_data(result_data: Variant) -> void:
	if mesh_received:
		return
	if multiplayer.get_unique_id() != 1:
		return

	mesh_received = true
	
	# Check for typed response (new format with 'type' field)
	if result_data is Dictionary and result_data.has("type"):
		var data_type: String = result_data.get("type", "mesh")
		match data_type:
			"mesh":
				_handle_mesh_response(result_data)
			"volume":
				_handle_volume_response(result_data)
			_:
				push_error("DynamicMeshSpecimen: Unsupported data type '%s'" % data_type)
				mesh_received = false
	else:
		# Legacy format (direct mesh data without type field)
		_handle_mesh_response(result_data)


func _handle_mesh_response(result_data: Dictionary) -> void:
	var data = MeshData.new()
	data.set_from_dict(result_data)
	_mesh_data = data
	_set_and_send_mesh(data)


func _handle_volume_response(result_data: Dictionary) -> void:
	# Volume data received — we need to switch to volume rendering
	# For now, convert to mesh using marching cubes client-side, or notify user
	push_warning("DynamicMeshSpecimen: Received volume data — volume rendering not yet supported in this specimen type")
	
	# Store the volume data for potential use
	var volume_data = VolumetricData.new()
	volume_data.set_from_dict(result_data)
	
	if volume_data.is_valid():
		# Emit signal or handle volume display
		# For now, we could try to extract an isosurface
		print("DynamicMeshSpecimen: Volume loaded: %s" % str(volume_data.get_dimensions()))
		# TODO: Add marching cubes conversion or switch specimen type
	
	if ui_instance:
		ui_instance.get_node("LoadingLayer").hide()


func _generate_specimen_menu(specimen_names: Array) -> void:
	if ui_instance == null:
		return
	var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
	specimen_list.clear()
	for specimen_name in specimen_names:
		specimen_list.add_item(specimen_name)


# ---------------------------------------------------------------------------
# Direct Data URL Loading (for curated specimens from main menu)
# ---------------------------------------------------------------------------

var _data_http_request: HTTPRequest


## Load specimen data directly from a URL (e.g., /api/specimens/{id}/data).
## Downloads the file and processes it using the existing mesh loading pipeline.
func _load_from_data_url() -> void:
	if data_url.is_empty():
		push_error("DynamicMeshSpecimen: data_url is empty")
		return

	print("DynamicMeshSpecimen: Loading from URL: %s" % data_url)

	if ui_instance:
		ui_instance.get_node("LoadingLayer").show()
		ui_instance.get_node("%SpecimenLayer").hide()

	# Create HTTP request for downloading the file
	_data_http_request = HTTPRequest.new()
	_data_http_request.request_completed.connect(_on_data_url_completed)
	add_child(_data_http_request)

	var err = _data_http_request.request(data_url)
	if err != OK:
		push_error("DynamicMeshSpecimen: Failed to start data request: %s" % error_string(err))
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()


func _on_data_url_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _data_http_request:
		_data_http_request.queue_free()
		_data_http_request = null

	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("DynamicMeshSpecimen: Data request failed: result=%d" % result)
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	if response_code != 200:
		push_error("DynamicMeshSpecimen: Data HTTP %d" % response_code)
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	# Check Content-Type to determine if response is JSON (dynamic specimen)
	var content_type = _get_content_type_from_headers(headers)
	if content_type.begins_with("application/json") or content_type.begins_with("text/json"):
		# JSON response — parse as mesh/volume data
		print("DynamicMeshSpecimen: Downloaded %d bytes, parsing as JSON" % body.size())
		var json_string = body.get_string_from_utf8()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result != OK:
			push_error("DynamicMeshSpecimen: Failed to parse JSON: %s" % json.get_error_message())
			if ui_instance:
				ui_instance.get_node("LoadingLayer").hide()
			return
		
		var result_data = json.get_data()
		_on_http_data(result_data)
		return

	# Otherwise, treat as binary file (STL, GLB, etc.)
	# Determine file extension from Content-Disposition header or URL
	var file_ext = _get_file_extension_from_headers(headers)
	if file_ext.is_empty():
		file_ext = _get_file_extension_from_url(data_url)
	if file_ext.is_empty():
		file_ext = "stl"  # Default to STL

	# Save to temp file
	var temp_path = "user://temp_specimen." + file_ext
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		push_error("DynamicMeshSpecimen: Failed to create temp file")
		if ui_instance:
			ui_instance.get_node("LoadingLayer").hide()
		return

	file.store_buffer(body)
	file.close()

	print("DynamicMeshSpecimen: Downloaded %d bytes, loading as .%s" % [body.size(), file_ext])

	# Load the file using the existing pipeline from MeshSpecimen
	_send_after_load = true
	_load_file(temp_path)


func _get_content_type_from_headers(headers: PackedStringArray) -> String:
	for header in headers:
		var lower = header.to_lower()
		if lower.begins_with("content-type:"):
			# Extract content type, strip params like charset
			var value = header.substr(14).strip_edges()  # len("content-type: ") = 14
			var semicolon = value.find(";")
			if semicolon != -1:
				value = value.substr(0, semicolon).strip_edges()
			return value.to_lower()
	return ""


func _get_file_extension_from_headers(headers: PackedStringArray) -> String:
	for header in headers:
		var lower = header.to_lower()
		if lower.begins_with("content-disposition:"):
			# Look for filename="something.ext"
			var start = header.find('filename="')
			if start != -1:
				start += 10  # len('filename="')
				var end = header.find('"', start)
				if end != -1:
					var filename = header.substr(start, end - start)
					return filename.get_extension().to_lower()
	return ""


func _get_file_extension_from_url(url: String) -> String:
	# Remove query params
	var path = url.split("?")[0]
	# Get the last path segment
	var segments = path.split("/")
	if segments.size() > 0:
		var filename = segments[-1]
		var ext = filename.get_extension()
		if ext:
			return ext.to_lower()
	return ""


# ---------------------------------------------------------------------------
# Job-based Dynamic Specimen Loading (via AscribeLinkClient)
# ---------------------------------------------------------------------------


func _load_dynamic_specimen(specimen_id: String, params: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	_active_job_id = specimen_id
	_message_log.clear()
	_link_client.run_job(specimen_id, params, _room_id)


func _on_job_progress(text: String) -> void:
	_append_message(text)
	_rpc_progress.rpc(text)


func _on_job_complete(result: Dictionary) -> void:
	_on_http_data(result)  # existing mesh/volume dispatch
	_rpc_job_done.rpc()
	_active_job_id = ""


func _on_job_error(error: String) -> void:
	push_error("Job failed: " + error)
	_append_message("Error: " + error)
	_rpc_job_error.rpc(error)
	_active_job_id = ""


func _append_message(text: String) -> void:
	_message_log.append(text)
	if _message_log.size() > MESSAGE_LOG_CAP:
		_message_log = _message_log.slice(_message_log.size() - MESSAGE_LOG_CAP)
	_render_message(text)


func _render_message(text: String) -> void:
	if ui_instance == null:
		return
	var log := ui_instance.get_node_or_null("LoadingLayer/MessageLog")
	if log is RichTextLabel:
		log.append_text(text + "\n")


@rpc("authority", "call_remote", "reliable")
func _rpc_progress(text: String) -> void:
	_append_message(text)


@rpc("authority", "call_remote", "reliable")
func _rpc_job_done() -> void:
	if ui_instance:
		ui_instance.get_node("LoadingLayer").hide()


@rpc("authority", "call_remote", "reliable")
func _rpc_job_error(error: String) -> void:
	_append_message("Error: " + error)


func _on_peer_connected(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if _active_job_id.is_empty():
		return
	_rpc_sync_state.rpc_id(peer_id, _active_job_id, _message_log)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_state(job_specimen_id: String, backlog: Array) -> void:
	# Render the backlog so the joiner sees the current state of the load.
	if ui_instance:
		ui_instance.get_node("LoadingLayer").show()
	var log = null
	if ui_instance:
		log = ui_instance.get_node_or_null("LoadingLayer/MessageLog")
	if log is RichTextLabel:
		log.clear()
	for text in backlog:
		_append_message(str(text))
