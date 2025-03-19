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
    
var loading_scenes: Array[String] = []

func process_scene_load():
    for loading_scene in loading_scenes:
        var progress: Array[int] = []
        var status: int = ResourceLoader.load_threaded_get_status(loading_scene, progress)
        print_debug(loading_scene, progress)
    
        if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
            loading_scenes.erase(loading_scene)
        elif status == ResourceLoader.THREAD_LOAD_LOADED:
            var scene = ResourceLoader.load_threaded_get(loading_scene)
            create_button(scene)
            loading_scenes.erase(loading_scene)
            print_debug('loading finished:', scene.resource_name)

func scan_and_create_buttons():
    if not dirty:
        return
        
    for n in %GridContainer.get_children():
        %GridContainer.remove_child(n)
        n.queue_free()

    var file_names = ResourceLoader.list_directory(scenes_directory)
    for file_name in file_names:
        if file_name.ends_with(".tscn"):
            print_debug("found specimen scene:", file_name)
            ResourceLoader.load_threaded_request(scenes_directory.path_join(file_name))
            loading_scenes.append(scenes_directory.path_join(file_name))
            #create_button(scenes_directory + "/" + file_name)
            
    dirty = false


func get_thumbnail(scene: PackedScene) -> Texture2D:
    var thumbnail_index: int = scene._bundled.names.find('thumbnail')
    if thumbnail_index > -1:
        return scene._bundled.variants[thumbnail_index] as CompressedTexture2D
    else:
        return null


func create_button(scene: PackedScene):
    if scene:
        var button = Button.new()
        button.text = scene.resource_name
        button.custom_minimum_size = button_size
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        button.connect("pressed", _on_scene_selected.bind(scene))

        %GridContainer.add_child(button)
        #button.set_owner(get_tree().edited_scene_root)

        var thumbnail: Texture2D = get_thumbnail(scene)
        if thumbnail:  # Ensure the scene provides a thumbnail atrribute
            var vbox = VBoxContainer.new()
            vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

            var label = Label.new()
            label.text = button.text
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.set("theme_override_font_sizes/font_size", 50)
            label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            vbox.add_child(label)

            var texture_rect = TextureRect.new()
            texture_rect.texture = thumbnail
            texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH  # Ensures icon scales properly
            texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            texture_rect.custom_minimum_size = Vector2(button_size.x * 0.8, button_size.y * 0.8)  # Scale within button
            vbox.add_child(texture_rect)

            button.add_child(vbox)

            #texture_rect.set_owner(get_tree().edited_scene_root)
            #label.set_owner(get_tree().edited_scene_root)
            #vbox.set_owner(get_tree().edited_scene_root)





func _on_scene_selected(scene: PackedScene):
    Ascribemain.load_3d_scene(scene)
