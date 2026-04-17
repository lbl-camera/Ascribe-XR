extends Node3D

## SceneManager singleton — orchestrates specimen loading across multiplayer peers.
##
## Every peer loads specimens independently by running the same RPCs locally.
## For static specimens, each peer downloads data directly from ascribe-link.
## For dynamic specimens, all peers show a shared ProceduralLinkUI form;
## when one peer submits, that peer runs the job and RPCs progress to the rest,
## then each peer fetches the final result from the server's per-room cache.

var world_3d: Node3D
var current_3d_scene: Node3D
var mainmenu: Node3D
var specimens_root: Node3D

var _active_procedural_ui: Panel = null
var _active_specimen_id: String = ""
var _active_function_name: String = ""
var _active_room_id: String = ""
var _active_params: Dictionary = {}
var _is_submitter: bool = false
## Held as a member so the job coroutine and its signal connections survive
## past _run_job returning. AscribeLinkClient is RefCounted, so a local ref
## would be freed before the HTTP polling loop finishes.
var _active_job_client: AscribeLinkClient = null


func _ready() -> void:
	world_3d = $/root/Main/Sketchfab_Scene
	mainmenu = $/root/Main/mainmenu
	specimens_root = $/root/Main/Specimens


var loading_scene: String


func _process(delta: float) -> void:
	process_scene_load()


## Entry point: load a specimen by scene path on all peers.
## Config is a Dictionary whose keys are names of @export properties on the
## specimen (e.g. data_url, display_name, story_text) that should be applied
## to the fresh instance before it enters the tree.
func load_3d_scene_path(new_scene: String) -> void:
	load_specimen.rpc(new_scene, {})


func load_3d_scene(new_scene: PackedScene) -> void:
	load_specimen.rpc(new_scene.resource_path, {})


func process_scene_load():
	# Kept for backwards compat with any callers still using the threaded loader.
	if loading_scene:
		var progress = []
		var status: int = ResourceLoader.load_threaded_get_status(loading_scene, progress)
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			loading_scene = ""
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene = ResourceLoader.load_threaded_get(loading_scene)
			loading_scene = ""
			load_specimen.rpc(scene.resource_path, {})


# ---------------------------------------------------------------------------
# Static / bundled specimen loading (one RPC, every peer does the same thing)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func load_specimen(scene_path: String, config: Dictionary) -> void:
	_reset_world()

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("SceneManager: Failed to load scene: %s" % scene_path)
		return

	var specimen: Specimen = packed.instantiate()
	_apply_config(specimen, config)

	current_3d_scene = specimen
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()
	hide_mainmenu()


func _apply_config(specimen: Node, config: Dictionary) -> void:
	for key in config.keys():
		if key in specimen:
			specimen.set(key, config[key])


func _reset_world() -> void:
	world_3d.show()
	$/root/Main/Floor.hide()
	$/root/Main/GPUParticles3D.emitting = true
	MenuManager.close_menu("specimen")
	MenuManager.close_menu("story")
	_close_procedural_ui()
	if current_3d_scene:
		current_3d_scene.queue_free()
		current_3d_scene = null


func _position_specimen(specimen: Specimen) -> void:
	match specimen.scale_mode:
		Specimen.ScaleMode.TABLE:
			specimens_root.global_position = world_3d.get_node("spawnmarker1").global_position
			set_room_scene(room_name)
		Specimen.ScaleMode.WORLD:
			specimens_root.global_position = Vector3(0, 0, 0)
			set_room_scene('world_scale')


# ---------------------------------------------------------------------------
# Dynamic specimen coordination
# ---------------------------------------------------------------------------

## Show the procedural-parameter form on every peer for the given specimen.
@rpc("any_peer", "call_local", "reliable")
func show_procedural_ui(specimen_id: String, metadata: Dictionary) -> void:
	_close_procedural_ui()

	_active_specimen_id = specimen_id
	_active_function_name = metadata.get("function_name", "")
	_is_submitter = false

	var procedural_ui_scene: PackedScene = preload("res://scenes/UI/procedural_link_ui.tscn")
	_active_procedural_ui = procedural_ui_scene.instantiate()
	_active_procedural_ui.schema = metadata.get("schema", {})
	_active_procedural_ui.function_name = _active_function_name
	_active_procedural_ui.metadata = metadata
	_active_procedural_ui.server_url = Config.ascribe_link_url

	MenuManager.show_menu(_active_procedural_ui, {
		"slot": "specimen",
		"screen_size": Vector2(3, 1.68),
		"viewport_size": Vector2(1152, 648),
	})

	hide_mainmenu()


## Called by any peer when its local ProceduralLinkUI submit button is pressed.
## The submitter runs the job; every peer transitions its UI to the loading state.
func request_submit(function_name: String, params: Dictionary) -> void:
	if _active_procedural_ui == null:
		push_warning("SceneManager: request_submit called with no active procedural UI")
		return
	_is_submitter = true
	var room_id = "ascribe"
	if Config.webrtcroomname:
		room_id = Config.webrtcroomname
	specimen_job_submitted.rpc(function_name, params, room_id)


@rpc("any_peer", "call_local", "reliable")
func specimen_job_submitted(function_name: String, params: Dictionary, room_id: String) -> void:
	_active_function_name = function_name
	_active_room_id = room_id
	_active_params = params
	if _active_procedural_ui and _active_procedural_ui.has_method("enter_loading_state"):
		_active_procedural_ui.enter_loading_state()

	# Only the peer that submitted (via request_submit) runs the job.
	if _is_submitter:
		_run_job(function_name, params, room_id)


func _run_job(function_name: String, params: Dictionary, room_id: String) -> void:
	_active_job_client = AscribeLinkClient.new(Config.ascribe_link_url)
	_active_job_client.setup(self)
	_active_job_client.job_progress.connect(_on_submitter_progress)
	_active_job_client.job_complete.connect(_on_submitter_complete)
	_active_job_client.job_error.connect(_on_submitter_error)
	_active_job_client.run_job(function_name, params, room_id)


func _on_submitter_progress(text: String) -> void:
	specimen_progress.rpc(text)


func _on_submitter_complete(result: Dictionary) -> void:
	# Every peer (including the submitter) fetches the result from the room
	# cache via the /data endpoint. The submitter just finished computing it,
	# so the cache is warm for everyone.
	specimen_job_done.rpc(_active_specimen_id, _active_function_name, _active_room_id)
	_active_job_client = null


func _on_submitter_error(error: String) -> void:
	specimen_job_error.rpc(error)
	_active_job_client = null


@rpc("any_peer", "call_local", "reliable")
func specimen_progress(text: String) -> void:
	if _active_procedural_ui and _active_procedural_ui.has_method("append_progress"):
		_active_procedural_ui.append_progress(text)


@rpc("any_peer", "call_local", "reliable")
func specimen_job_done(specimen_id: String, function_name: String, room_id: String) -> void:
	# Each peer independently fetches the cached result and loads it as a mesh.
	_fetch_and_load_result(specimen_id, function_name, room_id)


@rpc("any_peer", "call_local", "reliable")
func specimen_job_error(error: String) -> void:
	if _active_procedural_ui and _active_procedural_ui.has_method("show_error"):
		_active_procedural_ui.show_error(error)


func _fetch_and_load_result(specimen_id: String, function_name: String, room_id: String) -> void:
	# Use POST /api/specimens/{id}/data with the same params+room_id that the
	# submitter used — the server's RoomResultCache gives every peer the same
	# result without recomputing.
	var metadata := await _fetch_metadata_for_active(specimen_id)

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30.0
	var url := "%s/api/specimens/%s/data" % [Config.ascribe_link_url, specimen_id]
	var body := JSON.stringify({"params": _active_params, "room_id": room_id})
	var err := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("SceneManager: Failed to POST /data: %s" % error_string(err))
		http.queue_free()
		return
	var response = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var http_code: int = response[1]
	var payload: PackedByteArray = response[3]
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code != 200:
		push_error("SceneManager: /data failed: HTTP %d, body=%s" % [http_code, payload.get_string_from_utf8().substr(0, 200)])
		return

	var result_json = JSON.parse_string(payload.get_string_from_utf8())
	if not (result_json is Dictionary):
		push_error("SceneManager: Invalid /data response")
		return

	_build_specimen_from_result(result_json, metadata)


func _fetch_metadata_for_active(specimen_id: String) -> Dictionary:
	if _active_procedural_ui and _active_procedural_ui.metadata is Dictionary:
		return _active_procedural_ui.metadata
	var client := AscribeLinkClient.new(Config.ascribe_link_url)
	client.setup(self)
	return await client.fetch_specimen_metadata(specimen_id)


func _build_specimen_from_result(result: Dictionary, metadata: Dictionary) -> void:
	var result_type: String = result.get("type", "mesh")
	match result_type:
		"mesh":
			_load_mesh_from_result(result, metadata)
		"volume":
			push_warning("SceneManager: Volume result type not yet wired through the new flow")
		_:
			push_error("SceneManager: Unsupported result type: %s" % result_type)


func _load_mesh_from_result(result: Dictionary, metadata: Dictionary) -> void:
	_reset_world()

	var mesh_data := MeshData.new()
	mesh_data.set_from_dict(result)

	var packed: PackedScene = load("res://specimens/mesh_specimen.tscn")
	if packed == null:
		push_error("SceneManager: Failed to load mesh_specimen.tscn")
		return
	var specimen: Specimen = packed.instantiate()
	if specimen.has_method("set_mesh_data"):
		specimen.set_mesh_data(mesh_data)
	if "display_name" in specimen:
		specimen.display_name = metadata.get("display_name", specimen.display_name)

	current_3d_scene = specimen
	specimens_root.add_child(specimen)
	_position_specimen(specimen)
	specimen.show()
	hide_mainmenu()


func _close_procedural_ui() -> void:
	if _active_procedural_ui:
		MenuManager.close_menu("specimen")
		_active_procedural_ui = null


# ---------------------------------------------------------------------------
# Main menu toggle
# ---------------------------------------------------------------------------

func hide_mainmenu() -> void:
	if $/root/Main.is_ancestor_of(mainmenu):
		$/root/Main.remove_child(mainmenu)


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
