extends Panel

var dirty: bool = true

@export var scenes_directory: String = "res://specimens":
	set(value):
		if value != scenes_directory:
			dirty = true
			scenes_directory=value

@export var button_size: Vector2 = Vector2(556, 500): # Fixed button size
	set(value):
		if value != button_size:
			dirty = true
			button_size = value


# Called when the node enters the scene tree for the first time.
func _process(dt) -> void:
	scan_and_create_buttons()
	process_scene_load()

var scenes_to_load: Array[String] = []
var loading_scenes: Array[String] = []

var scenes: Array = []


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
				print_debug('Loading finished:', scene.resource_name)
				loading_scenes.remove_at(i)
	
	# Hide UI when done
	if loading_scenes.is_empty():
		$MarginContainer/VBoxContainer/LoadingLabel.hide()
		$MarginContainer/VBoxContainer/LoadingProgressBar.hide()


func scan_and_create_buttons():
	if not dirty:
		return

	%ItemList.clear()
	scenes.clear()

	var file_names = ResourceLoader.list_directory(scenes_directory)
	for file_name in file_names:
		if file_name.ends_with(".tscn"):
			scenes_to_load.append(scenes_directory.path_join(file_name))
	#create_button(scenes_directory + "/" + file_name)

	dirty = false


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
		scenes.append(scene)
		%ItemList.add_item(text, thumbnail)
		

func _on_item_list_item_clicked_not_dragged(index: Variant) -> void:
	Ascribemain.load_3d_scene(scenes[index])
