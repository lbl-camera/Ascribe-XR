@tool
extends Panel

var _scan_started: bool = false

@export var scenes_directory: String = "res://specimens"
			
@export var RebuldMenu: bool:
	set(value):
		rebuild_menu()
		
func _ready():
	for i in range(%ItemList.item_count):
		%ItemList.set_item_disabled(i, true)

# Called when the node enters the scene tree for the first time.
func _process(dt) -> void:
	if not _scan_started or not %ItemList.item_count:
		_scan_started = true
		scan_and_create_buttons()
	process_scene_load()

var scenes_to_load: Array[String] = []
var loading_scenes: Array[String] = []

var scenes: Dictionary = {}
@export var scenes_paths: Dictionary = {}

func rebuild_menu():
	scenes.clear()
	scenes_to_load.clear()
	loading_scenes.clear()
	%ItemList.clear()
	_scan_started = false

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
	#create_button(scenes_directory + "/" + file_name)


func get_property_from_scene(scene: PackedScene, property: String, default = null):
	var property_index: int = scene._bundled.names.find(property)
	if property_index > -1:
		return scene._bundled.variants[property_index] #as CompressedTexture2D
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
		

func _on_item_list_item_clicked_not_dragged(index: Variant) -> void:
	var text = %ItemList.get_item_text(index)
	if text in scenes:
		Ascribemain.load_3d_scene(scenes[text])
	else:
		Ascribemain.load_3d_scene_path(scenes_paths[text])
