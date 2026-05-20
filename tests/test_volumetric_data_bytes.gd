extends GdUnitTestSuite


func test_set_from_bytes_uint8():
	# 2x2x2 volume of uint8 values: 0..7 (row-major, [D,H,W] order)
	var voxels := PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7])
	var preamble := {
		"type": "volume",
		"shape": [2, 2, 2],
		"dtype": "uint8",
		"spacing": [1.0, 1.0, 1.0],
		"origin": [0.0, 0.0, 0.0],
	}

	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, voxels, 0)
	assert_that(ok).is_true()
	assert_that(data.get_dimensions()).is_equal(Vector3i(2, 2, 2))
	var tex := data.get_data()
	assert_that(tex).is_not_null()
	assert_that(tex is Texture3D).is_true()
	# Catches arg-order regressions on ImageTexture3D.create — depth=0 or
	# format=garbage both produce a non-null but broken texture.
	assert_that(tex.get_format()).is_equal(Image.FORMAT_L8)
	assert_that(tex.get_width()).is_equal(2)
	assert_that(tex.get_height()).is_equal(2)
	assert_that(tex.get_depth()).is_equal(2)


func test_set_from_bytes_float32():
	var body := PackedFloat32Array([1.5]).to_byte_array()
	var preamble := {
		"type": "volume",
		"shape": [1, 1, 1],
		"dtype": "float32",
		"spacing": [2.0, 2.0, 2.0],
		"origin": [10.0, 20.0, 30.0],
	}
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, body, 0)
	assert_that(ok).is_true()
	# Preamble order is [sz,sy,sx]; Godot Vector3 is [x,y,z] — so spacing should flip.
	assert_that(data.get_spacing()).is_equal(Vector3(2.0, 2.0, 2.0))
	var tex := data.get_data()
	assert_that(tex.get_format()).is_equal(Image.FORMAT_RF)
	assert_that(tex.get_depth()).is_equal(1)


func test_set_from_bytes_wrong_type_rejected():
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes({"type": "mesh"}, PackedByteArray(), 0)
	assert_that(ok).is_false()


func test_set_from_bytes_body_too_short():
	var preamble := {
		"type": "volume",
		"shape": [4, 4, 4],
		"dtype": "float32",
		"spacing": [1, 1, 1],
		"origin": [0, 0, 0],
	}
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, PackedByteArray([0, 0, 0, 0]), 0)
	assert_that(ok).is_false()


func test_set_from_bytes_missing_spacing_origin():
	# Server omits spacing/origin when None — client should default gracefully.
	var body := PackedByteArray([0])  # 1 uint8 voxel
	var preamble := {
		"type": "volume",
		"shape": [1, 1, 1],
		"dtype": "uint8",
	}
	var data := VolumetricData.new()
	var ok: bool = data.set_from_bytes(preamble, body, 0)
	assert_that(ok).is_true()
	assert_that(data.get_spacing()).is_equal(Vector3(1.0, 1.0, 1.0))
	assert_that(data.get_origin()).is_equal(Vector3(0.0, 0.0, 0.0))
