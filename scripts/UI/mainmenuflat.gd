@tool
extends Panel

## Main menu that displays available specimens.
## Tries to load from Ascribe-Link server first, falls back to local scene scanning.

var _scan_started: bool = false
var _ascribe_link_attempted: bool = false
var _ascribe_link_connected: bool = false

@export var scenes_directory: String = "res://specimens"

@export var RebuldMenu: bool:
	set(value):
		rebuild_menu()

# Ascribe-Link client
var _link_client: AscribeLinkClient
var _thumbnail_requests: Dictionary = {}  # specimen_id -> HTTPRequest


func _ready():
	for i in range(%ItemList.item_count):
		%ItemList.set_item_disabled(i, true)

	_link_client = AscribeLinkClient.new(Config.ascribe_link_url)
	_link_client.setup(self)
	_link_client.specimens_loaded.connect(_on_ascribe_link_specimens_loaded)
	_link_client.request_error.connect(_on_ascribe_link_error)

	scan_and_create_buttons()


func _process(dt) -> void:
	if not _scan_started or not %ItemList.item_count:
		_scan_started = true
		if not _ascribe_link_attempted:
			_ascribe_link_attempted = true
			_link_client.fetch_specimens()
	process_scene_load()


# ---------------------------------------------------------------------------
# Ascribe-Link Integration
# ---------------------------------------------------------------------------

## Remote specimens from Ascribe-Link (id -> metadata dict)
var remote_specimens: Dictionary = {}


func _on_ascribe_link_specimens_loaded(specimens: Array) -> void:
	_ascribe_link_connected = true

	for specimen in specimens:
		var id: String = specimen.get("id", "")
		var display_name: String = specimen.get("display_name", id)
		var thumbnail_url: String = specimen.get("thumbnail_url", "")
		var is_dynamic: bool = specimen.get("is_dynamic", false)

		if id.is_empty():
			continue

		remote_specimens[id] = specimen

		var list_label = display_name
		if is_dynamic:
			list_label += " ⚙️"

		# Dedup against static items baked into the .tscn (same pattern as create_button).
		var item_index := -1
		for i in range(%ItemList.item_count):
			if %ItemList.get_item_text(i) == list_label:
				item_index = i
				break
		if item_index == -1:
			item_index = %ItemList.add_item(list_label, null)
		else:
			%ItemList.set_item_disabled(item_index, false)
		%ItemList.set_item_metadata(item_index, {"remote": true, "id": id})

		if not thumbnail_url.is_empty():
			_fetch_thumbnail(id, list_label, Config.ascribe_link_url + thumbnail_url)


func _on_ascribe_link_error(error: String) -> void:
	push_warning("Ascribe-Link unavailable: %s. Using local specimens only." % error)
	_ascribe_link_connected = false


func _fetch_thumbnail(specimen_id: String, display_name: String, url: String) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	_thumbnail_requests[specimen_id] = http

	http.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
			_on_thumbnail_loaded(specimen_id, display_name, result, code, body)
			http.queue_free()
			_thumbnail_requests.erase(specimen_id)
	)

	var err = http.request(url)
	if err != OK:
		push_warning("Failed to request thumbnail for %s" % specimen_id)


func _on_thumbnail_loaded(specimen_id: String, display_name: String, result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return

	var image = Image.new()
	var err = image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_webp_from_buffer(body)
	if err != OK:
		push_warning("Failed to decode thumbnail for %s" % specimen_id)
		return

	var texture = ImageTexture.create_from_image(image)

	for i in range(%ItemList.item_count):
		var meta = %ItemList.get_item_metadata(i)
		if meta is Dictionary and meta.get("id", "") == specimen_id:
			%ItemList.set_item_icon(i, texture)
			break


# ---------------------------------------------------------------------------
# Local Scene Loading
# ---------------------------------------------------------------------------

var scenes_to_load: Array[String] = []
var loading_scenes: Array[String] = []

var scenes: Dictionary = {}
@export var scenes_paths: Dictionary = {}


func rebuild_menu():
	scenes.clear()
	scenes_to_load.clear()
	loading_scenes.clear()
	remote_specimens.clear()
	%ItemList.clear()
	_scan_started = false
	_ascribe_link_attempted = false
	_ascribe_link_connected = false


func process_scene_load():
	while scenes_to_load:
		var scene = scenes_to_load.pop_front()
		ResourceLoader.load_threaded_request(scene)
		loading_scenes.append(scene)

	if loading_scenes.is_empty():
		$MarginContainer/VBoxContainer/LoadingLabel.hide()
		$MarginContainer/VBoxContainer/LoadingProgressBar.hide()
		return

	var progress: Array[int] = []
	var status = ResourceLoader.load_threaded_get_status(loading_scenes[0], progress)
	$MarginContainer/VBoxContainer/LoadingProgressBar.value = progress[0] * 100.0
	$MarginContainer/VBoxContainer/LoadingLabel.text = "Loading " + loading_scenes[0] + " and %d others..." % (loading_scenes.size() - 1)

	for i in range(loading_scenes.size() - 1, -1, -1):
		var scene_name = loading_scenes[i]
		var scene_progress: Array[int] = []
		var scene_status = ResourceLoader.load_threaded_get_status(scene_name, scene_progress)

		match scene_status:
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error('Failed to load scene: ' + scene_name)
				loading_scenes.remove_at(i)

			ResourceLoader.THREAD_LOAD_LOADED:
				var scene = ResourceLoader.load_threaded_get(scene_name)
				if get_property_from_scene(scene, 'enabled', true):
					create_button(scene, scene_name)
					scenes_paths[get_property_from_scene(scene, "display_name", "")] = scene_name
				loading_scenes.remove_at(i)

	if loading_scenes.is_empty():
		$MarginContainer/VBoxContainer/LoadingLabel.hide()
		$MarginContainer/VBoxContainer/LoadingProgressBar.hide()
		%ItemList.sort_items_by_text()


func scan_and_create_buttons():
	var file_names = ResourceLoader.list_directory(scenes_directory)
	for file_name in file_names:
		if file_name.ends_with(".tscn"):
			scenes_to_load.append(scenes_directory.path_join(file_name))


func get_property_from_scene(scene: PackedScene, property: String, default = null):
	var property_index: int = scene._bundled.names.find(property)
	if property_index > -1:
		return scene._bundled.variants[property_index]
	else:
		return default


func create_button(scene: PackedScene, scene_path: String):
	if scene:
		var text = get_property_from_scene(scene, "display_name", "")
		var thumbnail: Texture2D = get_property_from_scene(scene, "thumbnail")
		scenes[text] = scene_path
		var item_index = -1
		for i in range(%ItemList.item_count):
			if %ItemList.get_item_text(i) == text:
				item_index = i
		if item_index == -1:
			%ItemList.add_item(text, thumbnail)
		else:
			%ItemList.set_item_disabled(item_index, false)


# ---------------------------------------------------------------------------
# Item Selection Handler
# ---------------------------------------------------------------------------

func _on_item_list_item_clicked_not_dragged(index: Variant) -> void:
	var text = %ItemList.get_item_text(index)
	var metadata = %ItemList.get_item_metadata(index)

	if metadata is Dictionary and metadata.get("remote", false):
		var specimen_id = metadata.get("id", "")
		_load_remote_specimen(specimen_id, text)
		return

	# Local scene — use the stored path so every peer can load it from disk.
	var path: String = scenes.get(text, scenes_paths.get(text, ""))
	if path.is_empty():
		push_error("MainMenuFlat: No scene path found for '%s'" % text)
		return
	SceneManager.load_specimen.rpc(path, {})


func _load_remote_specimen(specimen_id: String, display_name: String) -> void:
	var specimen_list_item = remote_specimens.get(specimen_id, {})
	var is_dynamic = specimen_list_item.get("is_dynamic", false)

	if is_dynamic:
		var metadata = await _link_client.fetch_specimen_metadata(specimen_id)
		if metadata.is_empty() or not metadata.has("schema"):
			push_error("Failed to fetch metadata for dynamic specimen: %s" % specimen_id)
			return
		SceneManager.show_procedural_ui.rpc(specimen_id, metadata)
		return

	var specimen_type = specimen_list_item.get("type", "mesh")
	var scene_path: String
	match specimen_type:
		"mesh":
			scene_path = "res://specimens/mesh_specimen.tscn"
		"volume":
			scene_path = "res://specimens/volume_specimen.tscn"
		_:
			scene_path = "res://specimens/mesh_specimen.tscn"

	var config = {
		"data_url": _link_client.get_specimen_data_url(specimen_id),
		"display_name": display_name,
		"story_text": specimen_list_item.get("story_text", []),
	}
	SceneManager.load_specimen.rpc(scene_path, config)
