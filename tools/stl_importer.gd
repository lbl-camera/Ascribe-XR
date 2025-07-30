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

func import(source_file):
	# STL file format: https://web.archive.org/web/20210428125112/http://www.fabbers.com/tech/STL_Format
	var file = FileAccess.open(source_file, FileAccess.READ)

	var mesh_data = null

	if is_ascii_stl(file):
		mesh_data = process_ascii_stl(file)
	else:
		mesh_data = process_binary_stl(file)

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


func process_binary_stl(file):
	var vertices = []
	var indices = []

	# Skip 80-byte header
	file.seek(80)

	# Read number of triangles
	var triangle_count = file.get_32()

	for i in range(triangle_count):
		# Skip normal
		for _1 in range(3):
			file.get_float()

		# Read the 3 vertices in STL order
		var v1 = [file.get_float(), file.get_float(), file.get_float()]
		var v2 = [file.get_float(), file.get_float(), file.get_float()]
		var v3 = [file.get_float(), file.get_float(), file.get_float()]

		# Flip order: STL CCW → Godot CW
		vertices.append_array(v3)
		indices.append(vertices.size() - 1)

		vertices.append_array(v2)
		indices.append(vertices.size() - 1)

		vertices.append_array(v1)
		indices.append(vertices.size() - 1)

		# Skip attribute byte count
		file.get_16()

	return {
		"vertices": vertices,
		"indices": indices
	}


func process_ascii_stl(file):
	var vertices = []
	var indices = []
	var vertex_map = {}  # For deduplication
	var next_index = 0
	var temp_face = []

	var parsing_state = PARSE_STATE.SOLID

	# Skip first line: "solid name"
	file.get_line()

	while not file.eof_reached():
		if parsing_state == PARSE_STATE.SOLID:
			var line = file.get_line().strip_edges(true, true)

			if line.begins_with("endsolid"):
				continue
			elif line != "":
				var parts = line.split(" ", false)
				if parts.size() >= 5 and parts[0] == "facet" and parts[1] == "normal":
					# You could store normals here if needed
					parsing_state = PARSE_STATE.FACET

		elif parsing_state == PARSE_STATE.FACET:
			var line = file.get_line().strip_edges(true, true)
			if line == "outer loop":
				temp_face.clear()
				parsing_state = PARSE_STATE.OUTER_LOOP
			elif line == "endfacet":
				parsing_state = PARSE_STATE.SOLID

		elif parsing_state == PARSE_STATE.OUTER_LOOP:
			var line = file.get_line().strip_edges(true, true)

			if line == "endloop":
				# STL is CCW; Godot wants CW, so reverse
				for v in temp_face.inverted():
					if not vertex_map.has(v):
						vertex_map[v] = next_index
						vertices.append(v)
						next_index += 1
					indices.append(vertex_map[v])
				parsing_state = PARSE_STATE.FACET
			elif line.begins_with("vertex"):
				var parts = line.split(" ", false)
				if parts.size() >= 4:
					var x = float(parts[1])
					var y = float(parts[2])
					var z = float(parts[3])
					temp_face.append(Vector3(x, y, z))

	return {
		"vertices": vertices,
		"indices": indices
	}


enum PARSE_STATE {SOLID, FACET, OUTER_LOOP}
