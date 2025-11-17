extends Specimen

var stl_importer = preload("res://tools/stl_importer.gd")
@export_file("*.stl", "*.fbx") var loading_file: String

@export var flip_normals: bool = false

var specimen_scene: Node3D
var specimen_collision: CollisionShape3D
var specimen_base_scale: float = 1
static var TABLE_SIZE: float   = 1


func _enter_tree():
	super._enter_tree()

	if loading_file:
		if loading_file.begins_with('uid://'):
			loading_file = ResourceUID.get_id_path(ResourceUID.text_to_id(loading_file))

		var mesh_data = load_path(loading_file)
		if mesh_data != null:
			set_mesh(mesh_data)
		ui_instance.get_node("%FileDialogLayer").hide()


	ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)
	ui_instance.get_node("%MaterialList").item_selected.connect(_on_materiallist_item_selected)

	#_on_file_dialog_file_selected(r"C:\Users\rp\Documents\vr-start\specimen_data\cow.obj")
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
		ui_instance.get_node("LoadingLayer").hide()
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		var mesh_resource = ResourceLoader.load_threaded_get(loading_file)
		if mesh_resource is PackedScene:
			var data = extract_mesh_data(find_mesh_instance(mesh_resource.instantiate()))
			set_and_send_mesh(data)
		elif mesh_resource is ArrayMesh:
			var data = extract_mesh_data(mesh_resource)
			set_and_send_mesh(data)
		else:
			if specimen_scene:
				specimen_scene.queue_free()
			set_pickable.rpc(mesh_resource.instantiate())
		loading_file = ""
		ui_instance.get_node("LoadingLayer").hide()



func _on_file_dialog_file_selected(path: String) -> void:
	var mesh_data = load_path(path)
	if mesh_data != null:
		set_and_send_mesh(mesh_data)

func load_fbx(path:String):
	var doc = FBXDocument.new()
	var state = FBXState.new()  # or maybe FBXState if available
	var err = doc.append_from_file(path, state)
	if err != OK:
		push_error("Failed to parse FBX: %s" % err)
		return
	var scene_root = doc.generate_scene(state)
	if not scene_root:
		push_error("FBXDocument.generate_scene returned null")
		return

	return scene_root

func load_path(path):
	var extension: String = path.get_extension()
	if extension == 'fbx':
		var scene = load_fbx(path)
		var mesh = combine_meshes_from_node(scene)
		var data = extract_mesh_data(mesh)
		return data
	elif extension == 'obj':
		ui_instance.get_node("LoadingLayer").show()
		ResourceLoader.load_threaded_request(path)
		loading_file = path
	elif extension == 'stl':
		var importer = stl_importer.new()
		var mesh_data = importer.import(path, flip_normals)
		return mesh_data
		#set_mesh.rpc([1,2,3, 2,3,4,5,6,7])

func build_mesh(data: Dictionary) -> ArrayMesh:
	var vertices = data.get("vertices", PackedVector3Array())
	var indices = data.get("indices", PackedInt32Array())
	var normals = data.get("normals", PackedVector3Array())

	# Convert flat float array to PackedVector3Array if needed
	if typeof(vertices) != TYPE_PACKED_VECTOR3_ARRAY:
		print("Converting vertices from flat array to PackedVector3Array")
		if vertices.size() % 3 != 0:
			push_error("Vertex array size (%d) is not a multiple of 3" % vertices.size())
			return null

		var v3_array = PackedVector3Array()
		v3_array.resize(vertices.size() / 3)
		for i in range(vertices.size() / 3):
			v3_array[i] = Vector3(vertices[i * 3], vertices[i * 3 + 1], vertices[i * 3 + 2])
		vertices = v3_array

	# Convert flat float array to PackedVector3Array for normals if needed
	if normals != null and normals.size() > 0 and typeof(normals) != TYPE_PACKED_VECTOR3_ARRAY:
		print("Converting normals from flat array to PackedVector3Array")
		if normals.size() % 3 != 0:
			push_error("Normal array size (%d) is not a multiple of 3" % normals.size())
			return null

		var n3_array = PackedVector3Array()
		n3_array.resize(normals.size() / 3)
		for i in range(normals.size() / 3):
			n3_array[i] = Vector3(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2])
		normals = n3_array

	# Validate data
	if vertices.size() == 0:
		push_error("No vertices to build mesh from.")
		return null

	if indices.size() == 0:
		push_error("No indices to build mesh from.")
		return null

	if indices.size() % 3 != 0:
		push_error("Index count (%d) is not a multiple of 3" % indices.size())
		return null

	# Validate indices are within bounds
	var max_index = -1
	for i in indices:
		if i < 0:
			push_error("Negative index found: %d" % i)
			return null
		if i >= vertices.size():
			push_error("Index out of bounds: %d (vertex count: %d)" % [i, vertices.size()])
			return null
		if i > max_index:
			max_index = i

	print("Building mesh: %d vertices, %d indices, %d normals" % [vertices.size(), indices.size(), normals.size()])

	if normals.size() > 0 and normals.size() != vertices.size():
		push_warning("Normal count (%d) doesn't match vertex count (%d)" % [normals.size(), vertices.size()])

	# Build mesh arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	if normals.size() == vertices.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	else:
		push_warning("Generating normals automatically due to size mismatch")
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for v in vertices:
			st.add_vertex(v)

		for i in indices:
			st.add_index(i)

		st.generate_normals()
		var result = st.commit()
		print("Mesh created via SurfaceTool with %d surfaces" % result.get_surface_count())
		return result

	# Create and return mesh
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Check if surface was added
	if mesh.get_surface_count() == 0:
		push_error("Failed to add surface to mesh!")
		push_error("Vertices type: %d, Indices type: %d, Normals type: %d" % [typeof(vertices), typeof(indices), typeof(normals)])
		return null

	print("Mesh created successfully with %d surfaces" % mesh.get_surface_count())

	return mesh

const CHUNK_SIZE = 20000

# Helper function to calculate chunk count
func _get_chunk_count(array_size: int) -> int:
	return ceili(float(array_size) / CHUNK_SIZE)

# Helper function to send array data in chunks
func _send_array_chunks(array, chunk_offset: int, total_chunks: int, field: String, is_final_array: bool) -> void:
	if array == null or array.size() == 0:
		return

	var local_chunk_count = _get_chunk_count(array.size())

	for i in range(local_chunk_count):
		var start_idx = i * CHUNK_SIZE
		var end_idx = mini((i + 1) * CHUNK_SIZE, array.size())
		var chunk = array.slice(start_idx, end_idx)

		var global_chunk_index = chunk_offset + i
		var is_last = is_final_array and (i == local_chunk_count - 1)

		receive_mesh_data.rpc(chunk, field, global_chunk_index, total_chunks, is_last)
		print("Sent %s chunk %d of %d" % [field, i + 1, local_chunk_count])

		await get_tree().process_frame

func send_mesh(data: Dictionary):
	var verts = data.get('vertices', PackedFloat32Array())
	var indices: PackedInt32Array = data.get('indices', PackedInt32Array())
	var normals = data.get('normals', PackedFloat32Array())
	
	# Convert PackedVector3Array to PackedFloat32Array if needed
	if typeof(verts) == TYPE_PACKED_VECTOR3_ARRAY:
		print("Converting vertices from PackedVector3Array to flat array")
		var flat_verts = PackedFloat32Array()
		flat_verts.resize(verts.size() * 3)
		for i in range(verts.size()):
			flat_verts[i * 3] = verts[i].x
			flat_verts[i * 3 + 1] = verts[i].y
			flat_verts[i * 3 + 2] = verts[i].z
		verts = flat_verts
	
	# Convert normals if they're PackedVector3Array
	if typeof(normals) == TYPE_PACKED_VECTOR3_ARRAY:
		print("Converting normals from PackedVector3Array to flat array")
		var flat_normals = PackedFloat32Array()
		flat_normals.resize(normals.size() * 3)
		for i in range(normals.size()):
			flat_normals[i * 3] = normals[i].x
			flat_normals[i * 3 + 1] = normals[i].y
			flat_normals[i * 3 + 2] = normals[i].z
		normals = flat_normals
	
	# Calculate total chunks
	var vert_chunks = _get_chunk_count(verts.size())
	var index_chunks = _get_chunk_count(indices.size()) if indices.size() > 0 else 0
	var normal_chunks = _get_chunk_count(normals.size()) if normals.size() > 0 else 0
	var total_chunks = vert_chunks + index_chunks + normal_chunks
	
	print("Sending mesh: %d vert chunks, %d index chunks, %d normal chunks" % [vert_chunks, index_chunks, normal_chunks])
	
	# Send vertices
	await _send_array_chunks(verts, 0, total_chunks, "vertices", index_chunks == 0 and normal_chunks == 0)
	
	# Send indices if present
	if index_chunks > 0:
		await _send_array_chunks(indices, vert_chunks, total_chunks, "indices", normal_chunks == 0)
	
	# Send normals if present
	if normal_chunks > 0:
		await _send_array_chunks(normals, vert_chunks + index_chunks, total_chunks, "normals", true)
# Received data storage
var received_data = {'vertices': PackedFloat32Array(),
					 'indices': PackedInt32Array(),
					 'normals': PackedFloat32Array()}

# Helper to update UI
func _update_receive_ui(index: int, total: int) -> void:
	ui_instance.get_node("LoadingLayer").show()
	ui_instance.get_node("%FileDialog").hide()
	ui_instance.get_node("%ProgressBar").value = index
	ui_instance.get_node("%ProgressBar").max_value = total
	
@rpc("any_peer", "call_remote", "reliable")
func receive_mesh_data(chunk, field:String, index: int, total: int, is_last: bool) -> void:
	_update_receive_ui(index, total)
	received_data[field].append_array(chunk)
	if is_last:
		set_mesh(received_data)
		received_data = {'vertices': PackedFloat32Array(),
						 'indices': PackedInt32Array(),
						 'normals': PackedFloat32Array()}

func set_mesh(data):
	print('mesh set on ', multiplayer.get_unique_id())
	# Handle the received mesh data
	var mesh = build_mesh(data)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY

	if specimen_scene:
		specimen_scene.queue_free()
	specimen_scene = mesh_instance
	set_pickable(mesh_instance)

func set_and_send_mesh(data):
	set_mesh(data)
	send_mesh(data)

func set_pickable(node:Node3D) -> void:
	make_pickable(node)
	ui_instance.get_node("%SettingsLayer").show()
	ui_instance.get_node("%MaterialMenu").show()
	ui_instance.get_node("%FileDialogLayer").hide()
	ui_instance.get_node("LoadingLayer").hide()


func make_pickable(node: Node3D):
	var collision: CollisionShape3D         = CollisionShape3D.new()
	var pickable = $ScalableMultiplayerPickableObject
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


func _on_materiallist_item_selected(index: int):
	var material_list: ItemList = ui_instance.get_node("%MaterialList")
	var material_name: String   = material_list.get_item_text(index)
	set_shader.rpc(material_name)

@rpc("any_peer", "call_local", "reliable")
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

func extract_mesh_data(mesh: ArrayMesh) -> Dictionary:
	var all_vertices: PackedFloat32Array = []
	var all_indices: PackedInt32Array = []
	var all_normals: PackedFloat32Array = []
	var vertex_offset := 0

	for surface in range(mesh.get_surface_count()):
		var primitive = mesh.surface_get_primitive_type(surface)
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			push_warning("Skipping surface %d (primitive type != TRIANGLES)" % surface)
			continue

		var arrays = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			push_warning("Skipping surface %d (no arrays)" % surface)
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			push_warning("Skipping surface %d (no vertices)" % surface)
			continue

		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

		# Flatten vertices
		for v in vertices:
			all_vertices.append(v.x)
			all_vertices.append(v.y)
			all_vertices.append(v.z)

		# Flatten normals (or generate placeholder normals if missing)
		if normals.size() == vertices.size():
			for n in normals:
				all_normals.append(n.x)
				all_normals.append(n.y)
				all_normals.append(n.z)
		else:
			push_warning("Surface %d has no normals or size mismatch, using placeholder normals" % surface)
			# Add placeholder normals (pointing up)
			for i in range(vertices.size()):
				all_normals.append(0.0)
				all_normals.append(1.0)
				all_normals.append(0.0)

		# Append indices (offset by vertex count)
		if indices.size() > 0:
			for i in indices:
				all_indices.append(i + vertex_offset)
		else:
			# If no indices, assume triangles in order
			var vertex_count = vertices.size()
			if vertex_count % 3 != 0:
				push_warning("Surface %d has non-triangular vertex count (%d)" % [surface, vertex_count])
				vertex_count -= vertex_count % 3
			for i in range(vertex_count):
				all_indices.append(i + vertex_offset)

		vertex_offset += vertices.size()

	# Final safety checks
	if all_vertices.size() % 3 != 0:
		push_error("Vertex array size (%d) not multiple of 3!" % all_vertices.size())

	if all_normals.size() % 3 != 0:
		push_error("Normal array size (%d) not multiple of 3!" % all_normals.size())

	if all_normals.size() != all_vertices.size():
		push_warning("Normal count (%d) doesn't match vertex count (%d)" % [all_normals.size() / 3, all_vertices.size() / 3])

	if all_indices.size() % 3 != 0:
		push_warning("Index array size (%d) not multiple of 3, truncating" % all_indices.size())
		var remainder = all_indices.size() % 3
		all_indices.resize(all_indices.size() - remainder)

	return {
		"vertices": all_vertices,
		"indices": all_indices,
		"normals": all_normals
	}

func find_mesh_instance(node: Node) -> ArrayMesh:
	if (node is MeshInstance3D or node is ImporterMeshInstance3D) and node.mesh:
		return node.mesh

	for child in node.get_children():
		var found = find_mesh_instance(child)
		if found:
			return found

	return null

func get_all_mesh_instances(node: Node) -> Array:
	var meshes := []
	if (node is MeshInstance3D or node is ImporterMeshInstance3D) and node.mesh:
		meshes.append(node)
	for child in node.get_children():
		meshes += get_all_mesh_instances(child)
	return meshes

func combine_meshes_from_node(root: Node) -> ArrayMesh:
	var combined_mesh := ArrayMesh.new()
	var arrays_per_surface := []
	#var materials := []

	var mesh_instances = get_all_mesh_instances(root)
	for mesh_instance in mesh_instances:
		var mesh = mesh_instance.mesh
		if mesh is ImporterMesh:
			mesh = mesh.get_mesh()
		if not mesh:
			continue

		var xform = mesh_instance.global_transform
		var basis = xform.basis
		var origin = xform.origin

		for s in mesh.get_surface_count():
			var arrays = mesh.surface_get_arrays(s)
			if arrays.size() == 0:
				continue

			# Clone arrays so we don't mutate the original mesh arrays
			var cloned := []
			cloned.resize(arrays.size())
			for i in range(arrays.size()):
				cloned[i] = arrays[i]

			# Transform vertices
			if cloned[Mesh.ARRAY_VERTEX] and cloned[Mesh.ARRAY_VERTEX].size() > 0:
				var verts : PackedVector3Array = cloned[Mesh.ARRAY_VERTEX]
				for i in range(verts.size()):
					# new_pos = basis * old_pos + origin
					verts[i] = basis * verts[i] + origin
				cloned[Mesh.ARRAY_VERTEX] = verts

			# Transform normals (if present)
			if cloned[Mesh.ARRAY_NORMAL] and cloned[Mesh.ARRAY_NORMAL].size() > 0:
				var norms : PackedVector3Array = cloned[Mesh.ARRAY_NORMAL]
				for i in range(norms.size()):
					norms[i] = (basis * norms[i]).normalized()
				cloned[Mesh.ARRAY_NORMAL] = norms

			# Tangents, colors, uvs, indices etc. are left unchanged (positions already transformed)
			arrays_per_surface.append(cloned)

			# store material for this surface (may be null)
			#var mat = mesh.surface_get_material(s)
			#materials.append(mat)

	# Add surfaces to combined mesh
	for i in range(arrays_per_surface.size()):
		var arr = arrays_per_surface[i]
		# Use triangles primitive; if your meshes use a different primitive, adapt accordingly.
		combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		# restore material if available
		#if materials[i]:
			#combined_mesh.surface_set_material(combined_mesh.get_surface_count() - 1, materials[i])

	return combined_mesh
