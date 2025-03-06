extends Panel

@export var scenes_directory: String = "res://specimens":
    set(value):
        scan_and_create_buttons()
        scenes_directory=value
        
@export var button_size: Vector2 = Vector2(1000, 1000):  # Fixed button size
    set(value):
        scan_and_create_buttons()
        button_size = value

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    scan_and_create_buttons()


func scan_and_create_buttons():
    for n in %GridContainer.get_children():
        %GridContainer.remove_child(n)
        n.queue_free() 
    
    var dir = DirAccess.open(scenes_directory)
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if file_name.ends_with(".tscn"):
                create_button(scenes_directory + "/" + file_name)
            file_name = dir.get_next()
    else:
        push_error("Failed to open directory: " + scenes_directory)

func create_button(scene_path: String):
    var scene = load(scene_path)
    if scene:
        var instance = scene.instantiate()
        var button = Button.new()
        button.text = scene_path.get_file().trim_suffix(".tscn")
        button.custom_minimum_size = button_size
        button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        button.connect("pressed", _on_scene_selected.bind(scene_path))

        %GridContainer.add_child(button)
        
        if 'thumbnail' in instance:  # Ensure the scene provides a thumbnail atrribute
            if instance.thumbnail:
                var icon: Texture2D = instance.thumbnail
                var texture_rect = TextureRect.new()
                texture_rect.texture = icon
                texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL  # Ensures icon scales properly
                texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                texture_rect.custom_minimum_size = Vector2(button_size.x * 0.8, button_size.y * 0.8)  # Scale within button
                
                var vbox = VBoxContainer.new()
                vbox.add_child(texture_rect)
                
                var label = Label.new()
                label.text = button.text
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                vbox.add_child(label)

                button.add_child(vbox)

        instance.queue_free()

func _on_scene_selected(scene_path: String):
    var scene = load(scene_path)
    if scene:
        Ascribemain.change_3d_scene(scene_path)
