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
	print("MainMenuFlat._ready() - Config.ascribe_link_url = ", Config.ascribe_link_url)
	
	for i in range(%ItemList.item_count):
		%ItemList.set_item_disabled(i, true)
	
	# Initialize Ascribe-Link client
	_link_client = AscribeLinkClient.new(Config.ascribe_link_url)
	_link_client.setup(self)
	_link_client.specimens_loaded.connect(_on_ascribe_link_specimens_loaded)
	_link_client.request_error.connect(_on_ascribe_link_error)
	
	# Start loading local specimens immediately (don't wait for server)
	# If server responds, it will add/override these
	print("MainMenuFlat: Starting local specimen scan...")
	scan_and_create_buttons()


func _process(dt) -> void:
	if not _scan_started or not %ItemList.item_count:
		_scan_started = true
		# Try Ascribe-Link first (with 2s timeout)
		if not _ascribe_link_attempted:
			_ascribe_link_attempted = true
			print("MainMenuFlat: Fetching specimens from ", Config.ascribe_link_url)
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
		var is_dynamic: bool = specimen.get("is_dynamic", false)
		
		if id.is_empty():
			continue
		
		remote_specimens[display_name] = specimen
		
		# Add visual indicator for dynamic specimens
		var list_label = display_name
		if is_dynamic:
			list_label += " ⚙️"
		
		# Add to list with placeholder, then fetch thumbnail
		var item_index = %ItemList.add_item(list_label, null)
		%ItemList.set_item_metadata(item_index, {"remote": true, "id": id})
		
		# Fetch thumbnail asynchronously
		if not thumbnail_url.is_empty():
			_fetch_thumbnail(id, display_name, Config.ascribe_link_url + thumbnail_url)
	
	# Note: Local specimens are already loading (started in _ready)
	# No need to call scan_and_create_buttons() again


func _on_ascribe_link_error(error: String) -> void:
	push_warning("Ascribe-Link unavailable: %s. Using local specimens only." % error)
	_ascribe_link_connected = false
	# Note: Local specimens are already loading (started in _ready)
	# No action needed here - just log that server is unavailable


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
	# Get basic metadata from cached list
	var specimen_list_item = remote_specimens.get(display_name, {})
	var is_dynamic = specimen_list_item.get("is_dynamic", false)
	
	# If dynamic, fetch full metadata and show procedural UI
	if is_dynamic:
		_load_dynamic_specimen(specimen_id, display_name)
		return
	
	# Otherwise, load static specimen directly
	var specimen_type = specimen_list_item.get("type", "mesh")
	
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
		
		# For volume specimens, we need to download and load the data
		if specimen_type == "volume":
			_load_remote_volume(instance, data_url_value, display_name, specimen_list_item)
			return
		
		# For mesh specimens, set the data URL for lazy loading
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
		var story = specimen_list_item.get("story_text", [])
		if "remote_story_text" in instance:
			instance.remote_story_text = story
		elif "story_text" in instance:
			instance.story_text = story
		
		SceneManager.change_3d_scene_instance(instance)
	else:
		push_error("Failed to load dynamic specimen scene: %s" % scene_path)


## Load a remote volume specimen — downloads data and configures volume rendering.
func _load_remote_volume(instance: Node3D, data_url: String, display_name: String, metadata: Dictionary) -> void:
	# Download the volume data
	var http = HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
			http.queue_free()
			_on_remote_volume_loaded(instance, result, code, body, display_name, metadata)
	)
	
	var err = http.request(data_url)
	if err != OK:
		push_error("Failed to request volume data: %s" % error_string(err))
		instance.queue_free()


func _on_remote_volume_loaded(
	instance: Node3D,
	result: int,
	code: int,
	body: PackedByteArray,
	display_name: String,
	metadata: Dictionary
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("Failed to download volume: result=%d, code=%d" % [result, code])
		instance.queue_free()
		return
	
	# Parse JSON response (volume data is JSON with base64 content)
	var json_str = body.get_string_from_utf8()
	var volume_dict = JSON.parse_string(json_str)
	
	if volume_dict == null:
		# Might be a raw binary file, try to load it directly
		# Save to temp file and load via Pipeline
		var temp_path = "user://temp_volume.bin"
		var file = FileAccess.open(temp_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			# TODO: Load via Pipeline.file_to_volume
			push_warning("Raw volume file loading not yet implemented for remote volumes")
		instance.queue_free()
		return
	
	# Volume data from API (JSON with base64)
	var volume_data = VolumetricData.new()
	volume_data.set_from_dict(volume_dict)
	
	if volume_data.is_valid():
		# Set display name
		if "display_name" in instance:
			instance.display_name = display_name
		
		# Get the volume texture and apply it
		var texture = volume_data.get_data()
		if texture and instance.has_method("_update_texture"):
			SceneManager.change_3d_scene_instance(instance)
			# Wait for instance to enter tree, then update texture
			await instance.tree_entered
			instance._update_texture(texture)
		else:
			push_error("Volume specimen missing _update_texture method")
			instance.queue_free()
	else:
		push_error("Invalid volume data from server")
		instance.queue_free()


# ---------------------------------------------------------------------------
# Dynamic Specimen Support (Procedural UI)
# ---------------------------------------------------------------------------

var _procedural_ui_instance: Panel = null
var _current_dynamic_specimen_id: String = ""
var _current_dynamic_metadata: Dictionary = {}


func _load_dynamic_specimen(specimen_id: String, display_name: String) -> void:
	print_debug("Loading dynamic specimen: %s" % specimen_id)
	
	# Fetch full metadata (includes schema)
	var metadata = await _link_client.fetch_specimen_metadata(specimen_id)
	
	if metadata.is_empty() or not metadata.has("schema"):
		push_error("Failed to fetch metadata for dynamic specimen: %s" % specimen_id)
		return
	
	_current_dynamic_specimen_id = specimen_id
	_current_dynamic_metadata = metadata
	
	# Show procedural UI in SpecimenUIViewport
	_show_procedural_ui(metadata)


func _show_procedural_ui(metadata: Dictionary) -> void:
	# Get the SpecimenUIViewport
	var viewport_3d = $/root/Main/SpecimenUIViewport
	if not viewport_3d:
		push_error("SpecimenUIViewport not found")
		return
	
	# Access the internal Viewport node
	var viewport = viewport_3d.get_node_or_null("Viewport")
	if not viewport:
		push_error("SpecimenUIViewport/Viewport not found")
		return
	
	# Clear existing UI
	if _procedural_ui_instance:
		_procedural_ui_instance.queue_free()
		_procedural_ui_instance = null
	
	# Instantiate ProceduralLinkUI
	var procedural_ui_scene = preload("res://scenes/UI/procedural_link_ui.tscn")
	_procedural_ui_instance = procedural_ui_scene.instantiate()
	
	# Set the schema
	_procedural_ui_instance.schema = metadata.get("schema", {})
	
	# Connect signals
	_procedural_ui_instance.ui_accept.connect(_on_procedural_ui_accept)
	_procedural_ui_instance.get_node("VBoxContainer/ButtonContainer/Button").pressed.connect(_on_procedural_ui_cancel)
	
	# Add to viewport
	viewport.add_child(_procedural_ui_instance)
	
	print_debug("Procedural UI shown for: %s" % metadata.get("display_name", ""))


func _on_procedural_ui_accept(params: Dictionary) -> void:
	print_debug("Procedural UI accepted with params: %s" % params)
	
	var function_name = _current_dynamic_metadata.get("function_name", "")
	if function_name.is_empty():
		push_error("No function_name in specimen metadata")
		return
	
	# Show loading state
	_show_loading_state()
	
	# Invoke the processing function (with room_id for multiplayer caching)
	var room_id = Config.webrtcroomname if Config.webrtcroomname else "ascribe"
	var result = await _link_client.invoke_processing_function(function_name, params, room_id)
	
	# Close the UI
	_hide_loading_state()
	if _procedural_ui_instance:
		_procedural_ui_instance.queue_free()
		_procedural_ui_instance = null
	
	if result.has("error"):
		_show_error_message("Processing failed: %s" % result.error)
		return
	
	# Interpret and display the result
	_display_processing_result(result, _current_dynamic_metadata)


func _on_procedural_ui_cancel() -> void:
	print_debug("Procedural UI cancelled")
	
	if _procedural_ui_instance:
		_procedural_ui_instance.queue_free()
		_procedural_ui_instance = null


func _display_processing_result(result: Dictionary, metadata: Dictionary) -> void:
	var result_type = result.get("type", "")
	
	match result_type:
		"mesh":
			_display_mesh_result(result, metadata)
		"volume":
			_display_volume_result(result, metadata)
		"point_cloud":
			push_warning("Point cloud display not yet implemented")
		"image":
			push_warning("Image display not yet implemented")
		_:
			push_error("Unknown result type: %s" % result_type)


func _display_mesh_result(result: Dictionary, metadata: Dictionary) -> void:
	var vertices = result.get("vertices", [])
	var indices = result.get("indices", [])
	var normals = result.get("normals")
	
	if vertices.is_empty() or indices.is_empty():
		push_error("Invalid mesh data: empty vertices or indices")
		return
	
	print_debug("Creating mesh: %d vertices, %d indices" % [vertices.size(), indices.size()])
	
	# Create ArrayMesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Convert flat vertices array to Vector3 array
	var vertex_array = PackedVector3Array()
	for i in range(0, vertices.size(), 3):
		vertex_array.append(Vector3(vertices[i], vertices[i+1], vertices[i+2]))
	arrays[Mesh.ARRAY_VERTEX] = vertex_array
	
	# Indices
	var index_array = PackedInt32Array()
	for idx in indices:
		index_array.append(idx)
	arrays[Mesh.ARRAY_INDEX] = index_array
	
	# Normals (if provided)
	if normals and normals.size() == vertices.size():
		var normal_array = PackedVector3Array()
		for i in range(0, normals.size(), 3):
			normal_array.append(Vector3(normals[i], normals[i+1], normals[i+2]))
		arrays[Mesh.ARRAY_NORMAL] = normal_array
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Load dynamic mesh specimen scene
	var scene = load("res://specimens/mesh_specimen.tscn")
	if not scene:
		push_error("Failed to load mesh_specimen.tscn")
		return
	
	var instance = scene.instantiate()
	
	# Set the mesh
	if instance.has_method("set_mesh"):
		instance.set_mesh(mesh)
	elif instance is MeshInstance3D:
		instance.mesh = mesh
	elif instance.has_node("MeshInstance3D"):
		instance.get_node("MeshInstance3D").mesh = mesh
	else:
		push_error("Mesh specimen doesn't have a way to set mesh")
		instance.queue_free()
		return
	
	# Set display name
	if "display_name" in instance:
		instance.display_name = metadata.get("display_name", "Generated Mesh")
	
	# Load the scene
	SceneManager.change_3d_scene_instance(instance)


func _display_volume_result(result: Dictionary, metadata: Dictionary) -> void:
	# Create VolumetricData and parse result
	var volume_data = VolumetricData.new()
	volume_data.set_from_dict(result)
	
	if not volume_data.is_valid():
		_show_error_message("Failed to parse volume data")
		return
	
	# Load volume specimen scene
	var scene = load("res://specimens/volume_specimen.tscn")
	if not scene:
		_show_error_message("Failed to load volume_specimen.tscn")
		return
	
	var instance = scene.instantiate()
	
	# Set display name
	if "display_name" in instance:
		instance.display_name = metadata.get("display_name", "Generated Volume")
	
	# Get the volume texture and apply it
	var texture = volume_data.get_data()
	if texture and instance.has_method("_update_texture"):
		SceneManager.change_3d_scene_instance(instance)
		# Wait for instance to enter tree, then update texture
		await instance.tree_entered
		instance._update_texture(texture)
	else:
		_show_error_message("Volume specimen missing _update_texture method")
		instance.queue_free()


# ---------------------------------------------------------------------------
# UI State Management (Loading & Error)
# ---------------------------------------------------------------------------

var _loading_panel: Panel = null
var _error_panel: Panel = null


func _show_loading_state() -> void:
	# Get the SpecimenUIViewport
	var viewport_3d = $/root/Main/SpecimenUIViewport
	if not viewport_3d:
		return
	
	var viewport = viewport_3d.get_node_or_null("Viewport")
	if not viewport:
		return
	
	# Hide form, show loading message
	if _procedural_ui_instance:
		_procedural_ui_instance.visible = false
	
	# Create loading panel
	_loading_panel = Panel.new()
	_loading_panel.anchor_right = 1.0
	_loading_panel.anchor_bottom = 1.0
	
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_panel.add_child(vbox)
	
	var label = Label.new()
	label.text = "⚙️ Generating..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Make it bigger and bold if possible
	label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(label)
	
	var spinner_label = Label.new()
	spinner_label.text = "⏳"
	spinner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spinner_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(spinner_label)
	
	viewport.add_child(_loading_panel)


func _hide_loading_state() -> void:
	if _loading_panel:
		_loading_panel.queue_free()
		_loading_panel = null


func _show_error_message(error_text: String) -> void:
	push_error(error_text)
	
	# Get the SpecimenUIViewport
	var viewport_3d = $/root/Main/SpecimenUIViewport
	if not viewport_3d:
		return
	
	var viewport = viewport_3d.get_node_or_null("Viewport")
	if not viewport:
		return
	
	# Clear any existing error
	if _error_panel:
		_error_panel.queue_free()
		_error_panel = null
	
	# Create error panel
	_error_panel = Panel.new()
	_error_panel.anchor_right = 1.0
	_error_panel.anchor_bottom = 1.0
	
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_error_panel.add_child(vbox)
	
	var icon_label = Label.new()
	icon_label.text = "❌"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(icon_label)
	
	var error_label = Label.new()
	error_label.text = "Error:\n" + error_text
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(error_label)
	
	var close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_hide_error_message)
	vbox.add_child(close_button)
	
	viewport.add_child(_error_panel)


func _hide_error_message() -> void:
	if _error_panel:
		_error_panel.queue_free()
		_error_panel = null
