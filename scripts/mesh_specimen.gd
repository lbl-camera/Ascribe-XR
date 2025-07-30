extends Specimen

var stl_importer = preload("res://tools/stl_importer.gd")
@export_file("*.stl", "*.fbx") var loading_file: String

var specimen_scene: Node3D
var specimen_collision: CollisionShape3D
var specimen_base_scale: float = 1
static var TABLE_SIZE: float   = 1


func _enter_tree():
	super._enter_tree()
	
	if loading_file:
		var mesh_data = load_path(loading_file)
		if mesh_data != null:
			set_mesh(mesh_data['vertices'])
		ui_instance.get_node("%FileDialog").hide()


	ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)
	ui_instance.get_node("%Scale").value_changed.connect(_on_scale_value_changed)
	ui_instance.get_node("%MaterialList").item_selected.connect(_on_materiallist_item_selected)

	#if OS.is_debug_build() and multiplayer.get_unique_id()==1:
		#_on_file_dialog_file_selected(r"C:\Users\rp\Documents\vr-start\skullandmore.stl")

## Return the [AABB] of the node.
func get_node_aabb(node: Node, exclude_top_level_transform: bool = true) -> AABB:
	var bounds: AABB = AABB()

	# Do not include children that is queued for deletion
	if node.is_queued_for_deletion():
		return bounds

	# Get the aabb of the visual instance
	if node is VisualInstance3D:
		bounds = node.get_aabb();

	# Recurse through all children
	for child in node.get_children():
		if "transform" not in child:
			continue
		var child_bounds: AABB = get_node_aabb(child, false)
		if bounds.size == Vector3.ZERO:
			bounds = child_bounds
		else:
			bounds = bounds.merge(child_bounds)

	if !exclude_top_level_transform:
		bounds = node.transform * bounds

	return bounds


func _process(delta: float) -> void:
	process_mesh_load()


func process_mesh_load() -> void:
	if not loading_file:
		return

	var progress    = []
	var status: int = ResourceLoader.load_threaded_get_status(loading_file, progress)
	ui_instance.get_node("%ProgressBar").value = progress[0]
	if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		loading_file = ""
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		var mesh_scene: PackedScene = ResourceLoader.load_threaded_get(loading_file)
		if specimen_scene:
			specimen_scene.queue_free()
		set_pickable.rpc(mesh_scene.instantiate())
		loading_file = ""



func _on_file_dialog_file_selected(path: String) -> void:
	var mesh_data = load_path(path)
	if mesh_data != null:
		set_and_send_mesh(mesh_data['vertices'])

	
func load_path(path):
	var extension: String = path.get_extension()
	if extension in ['fbx']:
		ui_instance.get_node("LoadingLayer").show()
		ResourceLoader.load_threaded_request(path)
		loading_file = path
	elif extension == 'stl':
		var importer = stl_importer.new()
		var mesh_data     = importer.import(path)
		return mesh_data
		#set_mesh.rpc([1,2,3, 2,3,4,5,6,7])

func build_mesh(vertices: Array, indices=null) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(len(vertices)/3):
		st.add_vertex(Vector3(vertices[i*3],vertices[i*3+1],vertices[i*3+2]))
			
	if indices != null:
		for index in indices:
			st.add_index(index)

	st.generate_normals()
	return st.commit()
	
const CHUNK_SIZE = 2000

func send_mesh(verts: Array, indices = null):
	var total_vert_chunks = int(ceil(float(verts.size()) / CHUNK_SIZE))
	for i in range(total_vert_chunks):
		var chunk = verts.slice(i * CHUNK_SIZE, (i+1)*CHUNK_SIZE if (i+1)*CHUNK_SIZE<=len(verts) else 0x7FFFFFFF)
		var is_last = (indices == null) and (i == total_vert_chunks - 1)
		receive_mesh_vertices.rpc(chunk, is_last)
		print("sent chunk ",i+1," of ", total_vert_chunks)
		await get_tree().process_frame  # Let the engine breathe

	if indices != null and indices.size() > 0:
		var total_index_chunks = int(ceil(float(indices.size()) / CHUNK_SIZE))
		for i in range(total_index_chunks):
			var chunk = indices.slice(i * CHUNK_SIZE, (i+1)*CHUNK_SIZE if (i+1)*CHUNK_SIZE<=len(indices) else 0x7FFFFFFF)
			var is_last = (i == total_index_chunks - 1)
			receive_mesh_indices.rpc(chunk, is_last)
			print("sent chunk ",i+1," of ", total_index_chunks)
			await get_tree().process_frame  # Let the engine breathe
		
var received_verts = []
var received_indices = []
		
@rpc("any_peer", "call_remote", "reliable")
func receive_mesh_vertices(chunk: Array, is_last: bool) -> void:
	received_verts.append_array(chunk)
	
	if is_last:
		# Finished receiving all vertex chunks
		set_mesh(received_verts)
		received_verts = []


@rpc("any_peer", "call_remote", "reliable")
func receive_mesh_indices(chunk: Array, is_last: bool) -> void:
	received_indices.append_array(chunk)
	
	if is_last:
		# Finished receiving all index chunks
		set_mesh(received_verts, received_indices)
		received_verts = []
		received_indices = []

func set_mesh(verts: Array, indices=null):
	print('mesh set on ', multiplayer.get_unique_id())
	# Handle the received mesh data
	var mesh = build_mesh(verts, indices)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY

	if specimen_scene:
		specimen_scene.queue_free()
	specimen_scene = mesh_instance
	set_pickable(mesh_instance)
	
func set_and_send_mesh(verts: Array, indices=null):
	set_mesh(verts, indices)
	send_mesh(verts, indices)

func set_pickable(node:Node3D) -> void:
	make_pickable(node)
	ui_instance.get_node("%SettingsLayer").show()
	ui_instance.get_node("%MaterialMenu").show()
	ui_instance.get_node("%FileDialog").hide()


func make_pickable(node: Node3D):
	var collision: CollisionShape3D         = CollisionShape3D.new()
	var pickable = $MultiplayerPickableObject
	pickable.add_child(node)
	pickable.add_child(collision)

	#specimen_scene = node
	#specimen_collision = collision

	var bounds = get_node_aabb(node)
	var base   = bounds.get_center()-Vector3(0, bounds.position.y/2, 0)
	collision.make_convex_from_siblings()
	specimen_base_scale = TABLE_SIZE/bounds.get_longest_axis_size()
	node.scale *= specimen_base_scale
	node.position -= base/bounds.get_longest_axis_size()
	collision.position -= base/bounds.get_longest_axis_size()
	collision.scale *= specimen_base_scale


func _on_scale_value_changed(value: float) -> void:
	if specimen_scene:
		specimen_scene.scale = specimen_base_scale * value * Vector3.ONE
		specimen_collision.scale = specimen_base_scale * value * Vector3.ONE


func _on_materiallist_item_selected(index: int):
	var material_list: ItemList = ui_instance.get_node("%MaterialList")
	var material_name: String   = material_list.get_item_text(index)
	set_shader(material_name)


func set_shader(material_name: String = "glass"):
	var shader_path = "res://shaders/" + material_name.to_lower() + ".gdshader"
	var shader_material_path = "res://shaders/" + material_name.to_lower() + ".tres"
	var material: ShaderMaterial = null
	if FileAccess.file_exists(shader_material_path):
		material = load(shader_material_path)
	else:
		material  = ShaderMaterial.new()
		var shader: Shader           = load("res://shaders/" + material_name.to_lower() + ".gdshader")
		material.shader = shader
	if material:
		specimen_scene.set_surface_override_material(0, material)
	else:
		print('Could not find material: ', material_name)
