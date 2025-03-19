extends Node3D


var world_3d : Node3D
var current_3d_scene : Node3D
var mainmenu : Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    world_3d = $/root/Main/Sketchfab_Scene
    mainmenu = $/root/Main/mainmenu
#    current_3d_scene = $mainmenu


var loading_scene: String

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
    process_scene_load()
    
func load_3d_scene_path(new_scene: String) -> void:
    ResourceLoader.load_threaded_request(new_scene)
    loading_scene = new_scene
    
func load_3d_scene(new_scene: PackedScene) -> void:
    change_3d_scene(new_scene)

func process_scene_load():
    if loading_scene:
        var progress = []
        var status: int = ResourceLoader.load_threaded_get_status(loading_scene, progress)
        print_debug(progress)
    
        if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
            loading_scene = ""
        elif status == ResourceLoader.THREAD_LOAD_LOADED:
            var scene = ResourceLoader.load_threaded_get(loading_scene)
            change_3d_scene(scene)
            loading_scene = ""

func change_3d_scene(new_scene: PackedScene, delete: bool = true, keep_running: bool = false) -> void:
    # reset world
    world_3d.show()
    $/root/Main/Floor.hide()

    if current_3d_scene != null:
        if delete:
            current_3d_scene.queue_free() # removes node entirely
        elif keep_running:
            current_3d_scene.visible = false # keeps in memory and running
        else:
            self.remove_child(current_3d_scene) # keeps in memory, does not run
    $/root/Main/GPUParticles3D.emitting = true
    var specimen: Specimen = new_scene.instantiate()
#    self.add_child(specimen)
    get_tree().create_timer(.5).timeout.connect(spawn_callback.bind(specimen))
    current_3d_scene = specimen

    match specimen.scale_mode:
        Specimen.ScaleMode.TABLE:
            # position over table
            specimen.global_position = world_3d.get_node("spawnmarker1").global_position

        Specimen.ScaleMode.WORLD:
            # hide environment
            world_3d.hide()
            $/root/Main/Floor.hide()

    toggle_mainmenu()

func toggle_mainmenu() -> void:
    if mainmenu.get_parent():
        $/root/Main.remove_child(mainmenu)
    else:
        $/root/Main.add_child(mainmenu)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action("ui_menu") and event.is_pressed():
        toggle_mainmenu()

func spawn_callback(node: Node3D) -> void:
    add_child(node)
