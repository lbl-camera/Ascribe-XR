extends Node3D
class_name DataSource

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
