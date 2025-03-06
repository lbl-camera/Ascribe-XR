extends Node3D

@export var world_3d : Node3D

var current_3d_scene : Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    current_3d_scene = $mainmenu


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
    pass

func change_3d_scene(new_scene: String, delete: bool = true, keep_running: bool = false) -> void:
    if current_3d_scene != null:
        if delete:
            current_3d_scene.queue_free() # removes node entirely
        elif keep_running:
            current_3d_scene.visible = false # keeps in memory and running
        else:
            self.remove_child(current_3d_scene) # keeps in memory, does not run
    var new = load(new_scene).instantiate()
    self.add_child(new)
    current_3d_scene = new
    
    print_debug(self)
    $/root/Main/Floor.hide()
    $/root/Main/mainmenu.hide()
