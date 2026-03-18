## Dynamic mesh specimen — loads meshes from Python via Ascribe-Link HTTP API.
## Uses HTTPSource for the data pipeline and AscribeLinkClient for catalog.
extends MeshSpecimen

var _http_source: HTTPSource
var _link_client: AscribeLinkClient
var _server_url: String

## Array of function info dicts from /api/processing/functions
var functions: Array = []
## Array of specimen info dicts from /api/specimens/
var specimens: Array = []

var mesh_received: bool = false


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

	# Initialize HTTP source for mesh processing requests
	_http_source = HTTPSource.new(_server_url)
	_http_source.setup(self)
	_http_source.data_available.connect(_on_http_data)
	_http_source.source_error.connect(func(e): push_error("HTTPSource: " + e))

	if ui_instance:
		var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
		specimen_list.item_selected.connect(_on_specimen_selected)
		ui_instance.get_node("%FileDialogLayer").hide()

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
	_http_source.set_request({
		"function_name": function_name,
		"args": [],
		"kwargs": {}
	})
	_http_source.fetch()


func _on_http_data(result_data: Variant) -> void:
	if mesh_received:
		return
	if multiplayer.get_unique_id() != 1:
		return

	mesh_received = true
	var data = MeshData.new()
	data.set_from_dict(result_data)
	_mesh_data = data
	_set_and_send_mesh(data)


func _generate_specimen_menu(specimen_names: Array) -> void:
	if ui_instance == null:
		return
	var specimen_list: ItemList = ui_instance.get_node('%SpecimenList')
	specimen_list.clear()
	for specimen_name in specimen_names:
		specimen_list.add_item(specimen_name)
