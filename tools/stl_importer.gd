extends Node

func data_from_arraymesh(array_mesh: ArrayMesh):
	var mesh_data = {
		"vertices": [],
		"indices": []
	}

	var surface_count = array_mesh.get_surface_count()
	for surface_index in range(surface_count):
		var arrays = array_mesh.surface_get_arrays(surface_index)
		if arrays.empty():
			continue
		
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]

		# Append or process per surface if needed
		mesh_data["vertices"] += vertices
		mesh_data["indices"] += indices

	return mesh_data

func import(source_file, flip_normals=false):
	# STL file format: https://web.archive.org/web/20210428125112/http://www.fabbers.com/tech/STL_Format
	var file = FileAccess.open(source_file, FileAccess.READ)

	var mesh_data = null

	if is_ascii_stl(file):
		mesh_data = process_ascii_stl(file)
	else:
		mesh_data = process_binary_stl(file)
		
	# Flip normals if requested
	if flip_normals:
		# Flip normal directions
		var normals: PackedVector3Array = mesh_data.normals
		for i in range(normals.size()):
			normals[i] = -normals[i]
		mesh_data['normals'] = normals
		print("Normals flipped")
		
		# Reverse winding order (swap every pair of vertices in each triangle)
		var indices: PackedInt32Array = mesh_data.indices
		for i in range(0, indices.size(), 3):
			# Swap second and third vertex of each triangle
			var tmp = indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = tmp
		mesh_data.indices = indices
		
		print("Normals and winding flipped")
	
	print("Loaded: %d vertices, %d indices, %d normals" % [
		mesh_data.vertices.size(),
		mesh_data.indices.size(),
		mesh_data.normals.size()
	])

	return mesh_data


func is_ascii_stl(file):
	# binary STL has a 80 character header which cannot begin with "solid"
	# ASCII STL begins with "solid"
	# so if first 5 bytes say "solid" it's an ASCII file

	var beginning_bytes = file.get_buffer(5)
	var is_ascii        = beginning_bytes.get_string_from_ascii() == "solid"

	# set the cursor back in the beginning of the file so the processing doesn't begin in a weird position
	file.seek(0)
	return is_ascii


func process_binary_stl(file: FileAccess) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var normals: PackedVector3Array = PackedVector3Array()
	
	file.big_endian = false  # STL is little-endian
	file.seek(80)
	var triangle_count = file.get_32()
	
	print("Binary STL: %d triangles" % triangle_count)
	
	for t in range(triangle_count):
		# Read facet normal
		var nx = file.get_float()
		var ny = file.get_float()
		var nz = file.get_float()
		var facet_normal = Vector3(nx, ny, nz)
		
		# Read triangle vertices
		var v1 = Vector3(file.get_float(), file.get_float(), file.get_float())
		var v2 = Vector3(file.get_float(), file.get_float(), file.get_float())
		var v3 = Vector3(file.get_float(), file.get_float(), file.get_float())
		
		# STL uses CCW winding, Godot uses CW winding
		# Reverse the vertex order: v1, v3, v2 instead of v1, v2, v3
		var base_idx = vertices.size()
		vertices.append(v1)
		vertices.append(v3)  # Swapped
		vertices.append(v2)  # Swapped
		
		indices.append(base_idx)
		indices.append(base_idx + 1)
		indices.append(base_idx + 2)
		
		normals.append(facet_normal)
		normals.append(facet_normal)
		normals.append(facet_normal)
		
		file.get_16()  # Skip attribute byte count
	
	return {
		"vertices": vertices,
		"indices": indices,
		"normals": normals
	}


func process_ascii_stl(file: FileAccess) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var normals: PackedVector3Array = PackedVector3Array()
	
	var parsing_state = PARSE_STATE.SOLID
	file.get_line() # skip "solid ..." line
	
	var normal = Vector3.ZERO
	var temp_face = []
	var triangle_count = 0
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges(true, true)
		if line == "":
			continue
		
		if parsing_state == PARSE_STATE.SOLID:
			var parts = line.split(" ", true)
			if parts.size() >= 5 and parts[0] == "facet" and parts[1] == "normal":
				normal = Vector3(float(parts[2]), float(parts[3]), float(parts[4]))
				parsing_state = PARSE_STATE.FACET
			elif line.begins_with("endsolid"):
				break
				
		elif parsing_state == PARSE_STATE.FACET:
			if line == "outer loop":
				temp_face.clear()
				parsing_state = PARSE_STATE.OUTER_LOOP
			elif line == "endfacet":
				parsing_state = PARSE_STATE.SOLID
				
		elif parsing_state == PARSE_STATE.OUTER_LOOP:
			if line.begins_with("vertex"):
				var p = line.split(" ", true)
				if p.size() >= 4:
					temp_face.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
				else:
					push_warning("Malformed vertex line: " + line)
			elif line == "endloop":
				if temp_face.size() == 3:
					triangle_count += 1
					
					# STL uses CCW winding, Godot uses CW winding
					# Reverse the vertex order
					var base_idx = vertices.size()
					vertices.append(temp_face[0])
					vertices.append(temp_face[2])  # Swapped
					vertices.append(temp_face[1])  # Swapped
					
					normals.append(normal)
					normals.append(normal)
					normals.append(normal)
					
					# Append indices
					indices.append(base_idx)
					indices.append(base_idx + 1)
					indices.append(base_idx + 2)
				else:
					push_warning("Malformed facet: " + str(temp_face.size()) + " vertices")
				
				parsing_state = PARSE_STATE.FACET
	
	print("ASCII STL: %d triangles" % triangle_count)
	
	return {
		"vertices": vertices,
		"indices": indices,
		"normals": normals
	}


enum PARSE_STATE {SOLID, FACET, OUTER_LOOP}
