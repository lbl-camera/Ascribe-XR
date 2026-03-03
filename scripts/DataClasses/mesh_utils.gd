## Static utility functions for mesh operations.
## Extracted from mesh_specimen.gd / DataSource.gd to avoid duplication.
class_name MeshUtils
extends RefCounted


## Build an ArrayMesh from a dictionary with vertices, indices, and normals.
## Accepts both flat arrays (PackedFloat32Array) and PackedVector3Array.
static func build_mesh(data: Dictionary) -> ArrayMesh:
	var vertices = data.get("vertices", PackedVector3Array())
	var indices = data.get("indices", PackedInt32Array())
	var normals = data.get("normals", PackedVector3Array())

	# Convert flat float array to PackedVector3Array if needed
	if typeof(vertices) != TYPE_PACKED_VECTOR3_ARRAY:
		vertices = unflatten_vector3(vertices)
		if vertices == null:
			return null

	# Convert flat float array to PackedVector3Array for normals if needed
	if normals != null and normals.size() > 0 and typeof(normals) != TYPE_PACKED_VECTOR3_ARRAY:
		normals = unflatten_vector3(normals)
		if normals == null:
			return null

	# Validate data
	if vertices.size() == 0:
		push_error("MeshUtils: No vertices to build mesh from.")
		return null

	if indices.size() == 0:
		push_error("MeshUtils: No indices to build mesh from.")
		return null

	if indices.size() % 3 != 0:
		push_error("MeshUtils: Index count (%d) is not a multiple of 3" % indices.size())
		return null

	# Validate indices are within bounds
	for i in indices:
		if i < 0:
			push_error("MeshUtils: Negative index found: %d" % i)
			return null
		if i >= vertices.size():
			push_error("MeshUtils: Index out of bounds: %d (vertex count: %d)" % [i, vertices.size()])
			return null

	if normals.size() > 0 and normals.size() != vertices.size():
		push_warning("MeshUtils: Normal count (%d) doesn't match vertex count (%d)" % [normals.size(), vertices.size()])

	# Build mesh arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	if normals.size() == vertices.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	else:
		# Generate normals via SurfaceTool
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in vertices:
			st.add_vertex(v)
		for i in indices:
			st.add_index(i)
		st.generate_normals()
		return st.commit()

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if mesh.get_surface_count() == 0:
		push_error("MeshUtils: Failed to add surface to mesh!")
		return null

	return mesh


## Extract mesh data (flat arrays) from an ArrayMesh.
## Returns {"vertices": PackedFloat32Array, "indices": PackedInt32Array, "normals": PackedFloat32Array}
static func extract_mesh_data(mesh: ArrayMesh) -> Dictionary:
	var all_vertices: PackedFloat32Array = []
	var all_indices: PackedInt32Array = []
	var all_normals: PackedFloat32Array = []
	var vertex_offset := 0

	for surface in range(mesh.get_surface_count()):
		var primitive = mesh.surface_get_primitive_type(surface)
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			continue

		var arrays = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

		for v in vertices:
			all_vertices.append(v.x)
			all_vertices.append(v.y)
			all_vertices.append(v.z)

		if normals.size() == vertices.size():
			for n in normals:
				all_normals.append(n.x)
				all_normals.append(n.y)
				all_normals.append(n.z)
		else:
			for i in range(vertices.size()):
				all_normals.append(0.0)
				all_normals.append(1.0)
				all_normals.append(0.0)

		if indices.size() > 0:
			for i in indices:
				all_indices.append(i + vertex_offset)
		else:
			var vertex_count = vertices.size()
			vertex_count -= vertex_count % 3
			for i in range(vertex_count):
				all_indices.append(i + vertex_offset)

		vertex_offset += vertices.size()

	if all_indices.size() % 3 != 0:
		var remainder = all_indices.size() % 3
		all_indices.resize(all_indices.size() - remainder)

	return {
		"vertices": all_vertices,
		"indices": all_indices,
		"normals": all_normals
	}


## Find the first MeshInstance3D (or ImporterMeshInstance3D) in a node tree and return its mesh.
static func find_mesh_instance(node: Node) -> ArrayMesh:
	if (node is MeshInstance3D or node is ImporterMeshInstance3D) and node.mesh:
		return node.mesh
	for child in node.get_children():
		var found = find_mesh_instance(child)
		if found:
			return found
	return null


## Get all MeshInstance3D nodes in a tree.
static func get_all_mesh_instances(node: Node) -> Array:
	var meshes := []
	if (node is MeshInstance3D or node is ImporterMeshInstance3D) and node.mesh:
		meshes.append(node)
	for child in node.get_children():
		meshes += get_all_mesh_instances(child)
	return meshes


## Combine all meshes under a node into a single ArrayMesh, applying transforms.
static func combine_meshes_from_node(root: Node) -> ArrayMesh:
	var combined_mesh := ArrayMesh.new()
	var arrays_per_surface := []

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

			var cloned := []
			cloned.resize(arrays.size())
			for i in range(arrays.size()):
				cloned[i] = arrays[i]

			if cloned[Mesh.ARRAY_VERTEX] and cloned[Mesh.ARRAY_VERTEX].size() > 0:
				var verts: PackedVector3Array = cloned[Mesh.ARRAY_VERTEX]
				for i in range(verts.size()):
					verts[i] = basis * verts[i] + origin
				cloned[Mesh.ARRAY_VERTEX] = verts

			if cloned[Mesh.ARRAY_NORMAL] and cloned[Mesh.ARRAY_NORMAL].size() > 0:
				var norms: PackedVector3Array = cloned[Mesh.ARRAY_NORMAL]
				for i in range(norms.size()):
					norms[i] = (basis * norms[i]).normalized()
				cloned[Mesh.ARRAY_NORMAL] = norms

			arrays_per_surface.append(cloned)

	for i in range(arrays_per_surface.size()):
		combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_per_surface[i])

	return combined_mesh


## Convert a flat PackedFloat32Array to PackedVector3Array.
static func unflatten_vector3(flat: PackedFloat32Array) -> PackedVector3Array:
	if flat.size() % 3 != 0:
		push_warning("MeshUtils: Array size (%d) is not a multiple of 3 — truncating" % flat.size())
		flat = flat.slice(0, flat.size() - (flat.size() % 3))
	var arr := PackedVector3Array()
	arr.resize(flat.size() / 3)
	for i in range(arr.size()):
		arr[i] = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
	return arr


## Convert PackedVector3Array to flat PackedFloat32Array.
static func flatten_vector3(arr: PackedVector3Array) -> PackedFloat32Array:
	var flat := PackedFloat32Array()
	flat.resize(arr.size() * 3)
	for i in range(arr.size()):
		flat[i * 3] = arr[i].x
		flat[i * 3 + 1] = arr[i].y
		flat[i * 3 + 2] = arr[i].z
	return flat


## Return the AABB of a node tree.
static func get_node_aabb(node: Node, exclude_top_level_transform: bool = true) -> AABB:
	var bounds: AABB = AABB()
	if node.is_queued_for_deletion():
		return bounds
	if node is VisualInstance3D:
		bounds = node.get_aabb()
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
