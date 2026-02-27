## Mesh specimen — loads mesh data via Pipeline and handles multiplayer sync.
extends Specimen
class_name MeshSpecimen

@export_file("*.stl", "*.fbx", "*.obj") var loading_file: String
@export var flip_normals: bool = false

var specimen_scene: Node3D
var _mesh_data: MeshData
var _threaded_loader: ThreadedLoader  # Kept for OBJ polling in _process
var specimen_base_scale: float = 1
static var TABLE_SIZE: float = 1


func _enter_tree():
	super._enter_tree()

	if loading_file:
		if loading_file.begins_with('uid://'):
			loading_file = ResourceUID.get_id_path(ResourceUID.text_to_id(loading_file))
		_load_file(loading_file)

	if ui_instance:
		ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)
		ui_instance.get_node("%MaterialList").item_selected.connect(_on_materiallist_item_selected)


func _process(delta: float) -> void:
	# Poll threaded loader for OBJ files
	if _threaded_loader:
		if _threaded_loader.poll():
			_threaded_loader.cleanup()
			_threaded_loader = null


## Load a mesh file using the pipeline.
func _load_file(path: String) -> void:
	var ext = path.get_extension().to_lower()

	if ext == "obj":
		# OBJ uses threaded loading (needs _process polling)
		_threaded_loader = ThreadedLoader.new()
		var target = MeshData.new()
		target.flip_normals = flip_normals
		_threaded_loader.load_complete.connect(_on_pipeline_complete)
		_threaded_loader.load_error.connect(_on_pipeline_error)
		_threaded_loader.load_progress.connect(_on_load_progress)
		var source = FileSource.new(path)
		source.data_available.connect(func(d): _threaded_loader.load_data(d, target))
		source.source_error.connect(_on_pipeline_error)
		source.fetch()
		if ui_instance:
			ui_instance.get_node("LoadingLayer").show()
	else:
		# STL/FBX use sync pipeline
		var p = Pipeline.file_to_mesh(path)
		p.pipeline_complete.connect(_on_pipeline_complete)
		p.pipeline_error.connect(_on_pipeline_error)
		# Set flip_normals on the target MeshData
		if p._target is MeshData:
			p._target.flip_normals = flip_normals
		p.run_pipeline()

	if ui_instance:
		ui_instance.get_node("%FileDialogLayer").hide()


func _on_pipeline_complete(data: Data) -> void:
	if data is MeshData:
		_mesh_data = data
		_set_and_send_mesh(data)


func _on_pipeline_error(error: String) -> void:
	push_error("MeshSpecimen pipeline error: %s" % error)
	if ui_instance:
		ui_instance.get_node("LoadingLayer").hide()


func _on_load_progress(progress: float) -> void:
	if ui_instance:
		ui_instance.get_node("%ProgressBar").value = progress


func _on_file_dialog_file_selected(path: String) -> void:
	_load_file(path)


# --- Mesh display ---

func _set_mesh_from_data(data: MeshData) -> void:
	var mesh = data.get_data()
	if mesh == null:
		push_error("MeshSpecimen: Failed to build mesh")
		return

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY

	if specimen_scene:
		specimen_scene.queue_free()
	specimen_scene = mesh_instance
	_set_pickable(mesh_instance)


func _set_and_send_mesh(data: MeshData) -> void:
	_set_mesh_from_data(data)
	_send_mesh(data.to_dict())


func _set_pickable(node: Node3D) -> void:
	_make_pickable(node)
	if ui_instance:
		ui_instance.get_node("%SettingsLayer").show()
		ui_instance.get_node("%MaterialMenu").show()
		ui_instance.get_node("%FileDialogLayer").hide()
		ui_instance.get_node("LoadingLayer").hide()


func _make_pickable(node: Node3D) -> void:
	var collision := CollisionShape3D.new()
	var pickable = $ScalableMultiplayerPickableObject
	pickable.add_child(node)
	pickable.add_child(collision)

	var bounds = MeshUtils.get_node_aabb(node)
	var base = bounds.get_center() - Vector3(0, bounds.position.y / 2, 0)
	collision.make_convex_from_siblings()
	specimen_base_scale = TABLE_SIZE / bounds.get_longest_axis_size()
	node.scale *= specimen_base_scale
	node.position -= base / bounds.get_longest_axis_size()
	collision.position -= base / bounds.get_longest_axis_size()
	collision.scale *= specimen_base_scale


# --- Multiplayer RPC mesh sync ---

func _get_chunk_count(array_size: int) -> int:
	return ceili(float(array_size) / Config.CHUNK_SIZE)


func _send_array_chunks(array, chunk_offset: int, total_chunks: int, field: String, is_final_array: bool) -> void:
	if array == null or array.size() == 0:
		return
	var local_chunk_count = _get_chunk_count(array.size())
	for i in range(local_chunk_count):
		var start_idx = i * Config.CHUNK_SIZE
		var end_idx = mini((i + 1) * Config.CHUNK_SIZE, array.size())
		var chunk = array.slice(start_idx, end_idx)
		var global_chunk_index = chunk_offset + i
		var is_last = is_final_array and (i == local_chunk_count - 1)
		_receive_mesh_data.rpc(chunk, field, global_chunk_index, total_chunks, is_last)
		await get_tree().process_frame


func _send_mesh(data: Dictionary) -> void:
	var verts = data.get('vertices', PackedFloat32Array())
	var indices: PackedInt32Array = data.get('indices', PackedInt32Array())
	var normals = data.get('normals', PackedFloat32Array())

	# Ensure flat arrays for chunking
	if typeof(verts) == TYPE_PACKED_VECTOR3_ARRAY:
		verts = MeshUtils.flatten_vector3(verts)
	if typeof(normals) == TYPE_PACKED_VECTOR3_ARRAY:
		normals = MeshUtils.flatten_vector3(normals)

	var vert_chunks = _get_chunk_count(verts.size())
	var index_chunks = _get_chunk_count(indices.size()) if indices.size() > 0 else 0
	var normal_chunks = _get_chunk_count(normals.size()) if normals.size() > 0 else 0
	var total_chunks = vert_chunks + index_chunks + normal_chunks

	await _send_array_chunks(verts, 0, total_chunks, "vertices", index_chunks == 0 and normal_chunks == 0)
	if index_chunks > 0:
		await _send_array_chunks(indices, vert_chunks, total_chunks, "indices", normal_chunks == 0)
	if normal_chunks > 0:
		await _send_array_chunks(normals, vert_chunks + index_chunks, total_chunks, "normals", true)


var _received_data = {
	'vertices': PackedFloat32Array(),
	'indices': PackedInt32Array(),
	'normals': PackedFloat32Array()
}


func _update_receive_ui(index: int, total: int) -> void:
	if ui_instance:
		ui_instance.get_node("LoadingLayer").show()
		ui_instance.get_node("%FileDialog").hide()
		ui_instance.get_node("%ProgressBar").value = index
		ui_instance.get_node("%ProgressBar").max_value = total


@rpc("any_peer", "call_remote", "reliable")
func _receive_mesh_data(chunk, field: String, index: int, total: int, is_last: bool) -> void:
	_update_receive_ui(index, total)
	_received_data[field].append_array(chunk)
	if is_last:
		var data = MeshData.new()
		data.set_from_dict(_received_data)
		_mesh_data = data
		_set_mesh_from_data(data)
		_received_data = {
			'vertices': PackedFloat32Array(),
			'indices': PackedInt32Array(),
			'normals': PackedFloat32Array()
		}


# --- Material / shader ---

func _on_materiallist_item_selected(index: int) -> void:
	var material_list: ItemList = ui_instance.get_node("%MaterialList")
	var material_name: String = material_list.get_item_text(index)
	_set_shader.rpc(material_name)


@rpc("any_peer", "call_local", "reliable")
func _set_shader(material_name: String = "glass") -> void:
	var shader_material_path = "res://shaders/" + material_name.to_lower() + ".tres"
	var material: ShaderMaterial = null
	if FileAccess.file_exists(shader_material_path):
		material = load(shader_material_path)
	else:
		var shader_path = "res://shaders/" + material_name.to_lower() + ".gdshader"
		material = ShaderMaterial.new()
		var shader: Shader = load(shader_path)
		material.shader = shader
	if material and specimen_scene:
		specimen_scene.set_surface_override_material(0, material)
	else:
		push_warning("Could not find material: %s" % material_name)
