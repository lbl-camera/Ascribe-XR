extends GdUnitTestSuite


func _build_mesh_envelope(vertices: PackedFloat32Array, indices: PackedInt32Array, normals: PackedFloat32Array) -> Dictionary:
	var preamble := {
		"type": "mesh",
		"vertex_count": vertices.size() / 3,
		"vertex_dtype": "float32",
		"index_count": indices.size(),
		"index_dtype": "uint32",
		"normal_count": normals.size() / 3,
		"normal_dtype": "float32",
	}
	var body := PackedByteArray()
	body.append_array(vertices.to_byte_array())
	body.append_array(indices.to_byte_array())
	body.append_array(normals.to_byte_array())
	return {"preamble": preamble, "body": body}


func test_set_from_bytes_with_normals():
	var verts := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	var inds := PackedInt32Array([0, 1, 2])
	var norms := PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0])
	var pkg := _build_mesh_envelope(verts, inds, norms)

	var data := MeshData.new()
	var ok: bool = data.set_from_bytes(pkg["preamble"], pkg["body"], 0)
	assert_that(ok).is_true()
	assert_that(data.vertices).is_equal(verts)
	assert_that(data.indices).is_equal(inds)
	assert_that(data.normals).is_equal(norms)


func test_set_from_bytes_without_normals():
	var verts := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	var inds := PackedInt32Array([0, 1, 2])
	var preamble := {
		"type": "mesh",
		"vertex_count": 3,
		"vertex_dtype": "float32",
		"index_count": 3,
		"index_dtype": "uint32",
		"normal_count": 0,
		"normal_dtype": "float32",
	}
	var body := PackedByteArray()
	body.append_array(verts.to_byte_array())
	body.append_array(inds.to_byte_array())

	var data := MeshData.new()
	var ok: bool = data.set_from_bytes(preamble, body, 0)
	assert_that(ok).is_true()
	assert_that(data.vertices).is_equal(verts)
	assert_that(data.indices).is_equal(inds)
	assert_that(data.normals.size()).is_equal(0)


func test_set_from_bytes_with_nonzero_offset():
	var verts := PackedFloat32Array([0.0, 0.0, 0.0])
	var inds := PackedInt32Array([0, 0, 0])
	var preamble := {
		"type": "mesh",
		"vertex_count": 1,
		"vertex_dtype": "float32",
		"index_count": 3,
		"index_dtype": "uint32",
		"normal_count": 0,
		"normal_dtype": "float32",
	}
	var prefix := PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF])
	var body := prefix.duplicate()
	body.append_array(verts.to_byte_array())
	body.append_array(inds.to_byte_array())

	var data := MeshData.new()
	var ok: bool = data.set_from_bytes(preamble, body, prefix.size())
	assert_that(ok).is_true()
	assert_that(data.vertices).is_equal(verts)
