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
	
	# Initialize Ascribe-Link client
	_link_client = AscribeLinkClient.new(Config.ascribe_link_url)
	_link_client.setup(self)
	_link_client.specimens_loaded.connect(_on_ascribe_link_specimens_loaded)
	_link_client.request_error.connect(_on_ascribe_link_error)


func _process(dt) -> void:
	if not _scan_started or not %ItemList.item_count:
		_scan_started = true
		# Try Ascribe-Link first
		if not _ascribe_link_attempted:
			_ascribe_link_attempted = true
			_link_client.fetch_specimens()
		else:
			# Fallback already triggered or waiting
			pass
	process_scene_load()


# ---------------------------------------------------------------------------
# Ascribe-Link Integration
# ---------------------------------------------------------------------------

## Remote specimens from Ascribe-Link (id -> metadata dict)
var remote_specimens: Dictionary = {}

func _on_ascribe_link_specimens_loaded(specimens: Array) -> void:
	_ascribe_link_connected = true
	print_debug("Ascribe-Link connected, %d specimens available" % specimens.size())
	
	for specimen in specimens:
		var id: String = specimen.get("id", "")
		var display_name: String = specimen.get("display_name", id)
		var thumbnail_url: String = specimen.get("thumbnail_url", "")
		
		if id.is_empty():
			continue
		
		remote_specimens[display_name] = specimen
		
		# Add to list with placeholder, then fetch thumbnail
		var item_index = %ItemList.add_item(display_name, null)
		%ItemList.set_item_metadata(item_index, {"remote": true, "id": id})
		
		# Fetch thumbnail asynchronously
		if not thumbnail_url.is_empty():
			_fetch_thumbnail(id, display_name, Config.ascribe_link_url + thumbnail_url)
	
	# Also load local specimens as fallback options
	scan_and_create_buttons()


func _on_ascribe_link_error(error: String) -> void:
	push_warning("Ascribe-Link unavailable: %s. Falling back to local specimens." % error)
	_ascribe_link_connected = false
	# Fall back to local scene scanning
	scan_and_create_buttons()


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
	
	# Try to load as image
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
	
	# Find and update the item
	for i in range(%ItemList.item_count):
		if %ItemList.get_item_text(i) == display_name:
			%ItemList.set_item_icon(i, texture)
			break


# ---------------------------------------------------------------------------
# Local Scene Loading (Original Fallback)
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
	# Queue new scenes for loading
	while scenes_to_load:
		var scene = scenes_to_load.pop_front()
		ResourceLoader.load_threaded_request(scene)
		loading_scenes.append(scene)
	
	if loading_scenes.is_empty():
		$MarginContainer/VBoxContainer/LoadingLabel.hide()
		$MarginContainer/VBoxContainer/LoadingProgressBar.hide()
		return
	
	# Update UI for first scene
	var progress: Array[int] = []
	var status = ResourceLoader.load_threaded_get_status(loading_scenes[0], progress)
	$MarginContainer/VBoxContainer/LoadingProgressBar.value = progress[0] * 100.0
	$MarginContainer/VBoxContainer/LoadingLabel.text = "Loading " + loading_scenes[0] + " and %d others..." % (loading_scenes.size() - 1)
	
	# Process all loading scenes (iterate backwards to safely remove)
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
					create_button(scene)
					scenes_paths[get_property_from_scene(scene, "display_name", "")] = scene_name
				print_debug('Loading finished:', scene.resource_name)
				loading_scenes.remove_at(i)
	
	# Hide UI when done
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


func create_button(scene: PackedScene):
	if scene:
		var text = get_property_from_scene(scene, "display_name", "")
		var thumbnail: Texture2D = get_property_from_scene(scene, "thumbnail")
		scenes[text] = scene
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
	
	# Check if this is a remote Ascribe-Link specimen
	if metadata is Dictionary and metadata.get("remote", false):
		var specimen_id = metadata.get("id", "")
		_load_remote_specimen(specimen_id, text)
		return
	
	# Otherwise, load local scene
	if text in scenes:
		SceneManager.load_3d_scene(scenes[text])
	else:
		SceneManager.load_3d_scene_path(scenes_paths[text])


func _load_remote_specimen(specimen_id: String, display_name: String) -> void:
	# Get full metadata from remote_specimens
	var specimen_data = remote_specimens.get(display_name, {})
	var specimen_type = specimen_data.get("type", "mesh")
	
	# Load the appropriate dynamic specimen scene based on type
	var scene_path: String
	match specimen_type:
		"mesh":
			scene_path = "res://specimens/dynamic_mesh_specimen.tscn"
		"volume":
			scene_path = "res://specimens/volume_specimen.tscn"
		_:
			scene_path = "res://specimens/dynamic_mesh_specimen.tscn"
	
	# Store the data URL for the specimen to fetch
	var data_url_value = _link_client.get_specimen_data_url(specimen_id)
	
	# Load the scene and configure it to fetch from URL
	var scene = load(scene_path)
	if scene:
		# Instantiate and configure with remote data source
		var instance = scene.instantiate()
		
		# Set the data URL
		if instance.has_method("set_data_url"):
			instance.set_data_url(data_url_value)
		elif "data_url" in instance:
			instance.data_url = data_url_value
		
		# Set display name (use remote_display_name for DynamicMeshSpecimen)
		if "remote_display_name" in instance:
			instance.remote_display_name = display_name
		elif "display_name" in instance:
			instance.display_name = display_name
		
		# Set story text if available
		var story = specimen_data.get("story_text", [])
		if "remote_story_text" in instance:
			instance.remote_story_text = story
		elif "story_text" in instance:
			instance.story_text = story
		
		SceneManager.change_3d_scene_instance(instance)
	else:
		push_error("Failed to load dynamic specimen scene: %s" % scene_path)
