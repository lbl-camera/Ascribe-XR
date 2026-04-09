extends Node3D

var world_3d: Node3D
var current_3d_scene: Node3D
var mainmenu: Node3D
var specimens_root: Node3D
var specimen_spawner: MultiplayerSpawner
var specimen_synchronizer: MultiplayerSynchronizer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	world_3d = $/root/Main/Sketchfab_Scene
	mainmenu = $/root/Main/mainmenu
	specimens_root = $/root/Main/Specimens
	specimen_spawner = $/root/Main/SpecimenSpawner
	specimen_synchronizer = $/root/Main/SpecimenSynchronizer
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
		var progress    = []
		var status: int = ResourceLoader.load_threaded_get_status(loading_scene, progress)
		print_debug(progress)

		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			loading_scene = ""
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene = ResourceLoader.load_threaded_get(loading_scene)
			change_3d_scene(scene)
			loading_scene = ""

@rpc("any_peer", "call_local", "reliable")
func prep_for_new_3d_scene():
	# reset world
	world_3d.show()
	$/root/Main/Floor.hide()
	MenuManager.close_menu("specimen")
	MenuManager.close_menu("story")
	if current_3d_scene:
		current_3d_scene.queue_free()
		current_3d_scene = null

func change_3d_scene(new_scene: PackedScene) -> void:
	var specimen: Specimen = new_scene.instantiate()
	change_3d_scene_instance(specimen)


## Load a pre-instantiated specimen (used for remote Ascribe-Link specimens)
func change_3d_scene_instance(specimen: Specimen) -> void:
	print("change_3d_scene_instance called")
	set_spawner_authority.rpc()
	prep_for_new_3d_scene.rpc()

	$/root/Main/GPUParticles3D.emitting = true
	specimen.hide()

	current_3d_scene = specimen
	get_tree().create_timer(.5).timeout.connect(post_change_3d_scene.rpc)

@rpc("any_peer", "call_local", "reliable")
func set_spawner_authority():
	specimen_spawner.set_multiplayer_authority(multiplayer.get_remote_sender_id())
	specimen_synchronizer.set_multiplayer_authority(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_local", "reliable")
func post_change_3d_scene():
	print("post_change_3d_scene called")
	var specimen = null
	if specimen_spawner.get_multiplayer_authority() == multiplayer.get_unique_id():
		specimens_root.add_child(current_3d_scene)
		specimen = current_3d_scene
	else:
		var i = 0
		while specimens_root.get_child_count() == 0 and i<1000:
			i+=1
			print(i)
			await get_tree().process_frame  # Let the engine breathe
		if i==1000:
			push_error('Unable to change specimen; ',multiplayer.get_remote_sender_id(),'->',multiplayer.get_unique_id())
			return
		else:
			specimen = specimens_root.get_child(0)

	match specimen.scale_mode:
		Specimen.ScaleMode.TABLE:
			# position over table
			specimens_root.global_position = world_3d.get_node("spawnmarker1").global_position
			set_room_scene(room_name)

		Specimen.ScaleMode.WORLD:
			# position at origin
			specimens_root.global_position = Vector3(0, 0, 0)
			# hide environment
			set_room_scene('world_scale')

	current_3d_scene = specimen
	specimen.show()

	hide_mainmenu()

func hide_mainmenu() -> void:
	print("hide_mainmenu called")
	if $/root/Main.is_ancestor_of(mainmenu):
		print("removing mainmenu from tree")
		$/root/Main.remove_child(mainmenu)
	else:
		print("mainmenu not in tree (already hidden or not found)")

func show_mainmenu() -> void:
	if not $/root/Main.is_ancestor_of(mainmenu):
		$/root/Main.add_child(mainmenu)

func toggle_mainmenu() -> void:
	if mainmenu:
		if mainmenu.get_parent():
			hide_mainmenu()
		else:
			show_mainmenu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("ui_menu") and event.is_pressed():
		toggle_mainmenu()


@export var room_name = 'lab'

func set_room_scene(name):
	match name:
		'lab':
			$/root/Main/Sketchfab_Scene.show()
			$/root/Main/XROrigin3D/OpenXRFbPassthroughGeometry.hide()
			$/root/Main/Black.hide()
			room_name = name
		'black':
			$/root/Main/Sketchfab_Scene.hide()
			$/root/Main/XROrigin3D/OpenXRFbPassthroughGeometry.hide()
			$/root/Main/Black.show()
			room_name = name
		'passthrough':
			$/root/Main/Sketchfab_Scene.hide()
			$/root/Main/XROrigin3D/OpenXRFbPassthroughGeometry.show()
			$/root/Main/Black.hide()
			room_name = name
		'world_scale':
			$/root/Main/Sketchfab_Scene.hide()
			$/root/Main/XROrigin3D/OpenXRFbPassthroughGeometry.hide()
			$/root/Main/Black.hide()
			room_name = name
