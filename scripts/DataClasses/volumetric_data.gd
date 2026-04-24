## Volumetric data container.
## Stores a 3D texture for volume rendering.
class_name VolumetricData
extends Data

var _texture: Texture3D
var _dimensions: Vector3i
var _spacing: Vector3 = Vector3.ONE
var _origin: Vector3 = Vector3.ZERO


func is_valid() -> bool:
	return _texture != null


func get_data() -> Texture3D:
	return _texture


func get_dimensions() -> Vector3i:
	return _dimensions


func get_spacing() -> Vector3:
	return _spacing


func get_origin() -> Vector3:
	return _origin


func set_texture(tex: Texture3D, dims: Vector3i) -> void:
	_texture = tex
	_dimensions = dims
	data_ready.emit()


func set_from_images(images: Array[Image], dims: Vector3i) -> void:
	var tex := ImageTexture3D.new()
	tex.create(dims.x, dims.y, dims.z, images[0].get_format(), false, images)
	_texture = tex
	_dimensions = dims
	data_ready.emit()


## Set data from a dictionary (as received from Ascribe-Link).
## Expects {"type": "volume", "shape": [...], "dtype": "...", "data": "<base64>", ...}
func set_from_dict(data: Dictionary) -> void:
	var shape = data.get("shape", [])
	var dtype: String = data.get("dtype", "float32")
	var b64_data: String = data.get("data", "")
	var spacing_arr = data.get("spacing", [1.0, 1.0, 1.0])
	var origin_arr = data.get("origin", [0.0, 0.0, 0.0])
	
	if shape.size() != 3:
		push_error("VolumetricData: shape must have 3 elements, got %d" % shape.size())
		return
	
	if b64_data.is_empty():
		push_error("VolumetricData: data is empty")
		return
	
	# Decode base64
	var raw_bytes = Marshalls.base64_to_raw(b64_data)
	if raw_bytes.is_empty():
		push_error("VolumetricData: failed to decode base64 data")
		return
	
	# Parse dimensions
	var depth: int = shape[0]
	var height: int = shape[1]
	var width: int = shape[2]
	_dimensions = Vector3i(width, height, depth)
	
	# Parse spacing/origin
	if spacing_arr.size() >= 3:
		_spacing = Vector3(spacing_arr[2], spacing_arr[1], spacing_arr[0])  # Reverse order: sz,sy,sx -> x,y,z
	if origin_arr.size() >= 3:
		_origin = Vector3(origin_arr[2], origin_arr[1], origin_arr[0])
	
	# Convert raw bytes to images based on dtype
	var images: Array[Image] = []
	var bytes_per_voxel := _get_bytes_per_voxel(dtype)
	var slice_size := width * height * bytes_per_voxel
	
	for z in range(depth):
		var slice_start := z * slice_size
		var slice_end := slice_start + slice_size
		var slice_bytes := raw_bytes.slice(slice_start, slice_end)
		
		var img := _create_image_from_bytes(slice_bytes, width, height, dtype)
		if img:
			images.append(img)
		else:
			push_error("VolumetricData: failed to create image for slice %d" % z)
			return
	
	# Create 3D texture
	if images.size() > 0:
		var tex := ImageTexture3D.new()
		tex.create(width, height, depth, images[0].get_format(), false, images)
		_texture = tex
		print("VolumetricData: Loaded %dx%dx%d volume (%s)" % [width, height, depth, dtype])
		data_ready.emit()


func _get_bytes_per_voxel(dtype: String) -> int:
	match dtype:
		"uint8", "int8":
			return 1
		"uint16", "int16", "float16":
			return 2
		"uint32", "int32", "float32":
			return 4
		"uint64", "int64", "float64":
			return 8
		_:
			push_warning("VolumetricData: unknown dtype '%s', assuming 4 bytes" % dtype)
			return 4


func _create_image_from_bytes(raw: PackedByteArray, width: int, height: int, dtype: String) -> Image:
	# For now, we normalize to 8-bit grayscale or use native format
	# Godot supports L8, LA8, R8, RG8, RGB8, RGBA8, RF, RGF, RGBF, RGBAF, etc.
	
	match dtype:
		"uint8":
			# Direct L8 format
			return Image.create_from_data(width, height, false, Image.FORMAT_L8, raw)
		
		"float32":
			# Convert to RF (32-bit float red channel)
			return Image.create_from_data(width, height, false, Image.FORMAT_RF, raw)
		
		"uint16":
			# Normalize to 8-bit for now (Godot doesn't have native 16-bit grayscale)
			var normalized := PackedByteArray()
			normalized.resize(width * height)
			for i in range(0, raw.size(), 2):
				var value := raw[i] | (raw[i + 1] << 8)
				normalized[i / 2] = clamp(value >> 8, 0, 255)  # Simple high-byte extraction
			return Image.create_from_data(width, height, false, Image.FORMAT_L8, normalized)
		
		"float64":
			# Convert float64 to float32 (RF format)
			var float32_bytes := PackedByteArray()
			float32_bytes.resize(width * height * 4)
			for i in range(0, raw.size(), 8):
				# Read float64, convert to float32
				var f64_bytes := raw.slice(i, i + 8)
				var f64 := f64_bytes.decode_double(0)
				float32_bytes.encode_float(i / 2, f64)
			return Image.create_from_data(width, height, false, Image.FORMAT_RF, float32_bytes)
		
		_:
			# Try to interpret as float32 by default
			push_warning("VolumetricData: treating '%s' as float32" % dtype)
			return Image.create_from_data(width, height, false, Image.FORMAT_RF, raw)


func clear() -> void:
	_texture = null
	_dimensions = Vector3i.ZERO
	_spacing = Vector3.ONE
	_origin = Vector3.ZERO


## Set data from the binary envelope body.
##
## `preamble` is the dict returned by `BinaryEnvelope.parse`.
## `body` is the full response body (including the 4-byte length prefix and JSON preamble).
## `offset` is the byte position where the volume bytes start (`preamble.offset` from the parser).
##
## Returns true on success, false on error (malformed preamble, body-too-short, bad dtype).
func set_from_bytes(preamble: Dictionary, body: PackedByteArray, offset: int) -> bool:
	if preamble.get("type", "") != "volume":
		push_error("VolumetricData.set_from_bytes: preamble.type is not 'volume'")
		return false

	var shape = preamble.get("shape", [])
	if shape.size() != 3:
		push_error("VolumetricData.set_from_bytes: shape must have 3 elements")
		return false
	var depth: int = int(shape[0])
	var height: int = int(shape[1])
	var width: int = int(shape[2])
	_dimensions = Vector3i(width, height, depth)

	var dtype: String = preamble.get("dtype", "float32")
	var bytes_per_voxel := _get_bytes_per_voxel(dtype)
	var slice_bytes := width * height * bytes_per_voxel
	var total_bytes := depth * slice_bytes

	if body.size() < offset + total_bytes:
		push_error("VolumetricData.set_from_bytes: body too short (need %d, got %d)" % [offset + total_bytes, body.size()])
		return false

	var spacing_arr = preamble.get("spacing", [1.0, 1.0, 1.0])
	var origin_arr = preamble.get("origin", [0.0, 0.0, 0.0])
	if spacing_arr == null:
		spacing_arr = [1.0, 1.0, 1.0]
	if origin_arr == null:
		origin_arr = [0.0, 0.0, 0.0]
	if spacing_arr.size() >= 3:
		# Preamble order is [sz, sy, sx]; Godot Vector3 is [x, y, z].
		_spacing = Vector3(spacing_arr[2], spacing_arr[1], spacing_arr[0])
	if origin_arr.size() >= 3:
		_origin = Vector3(origin_arr[2], origin_arr[1], origin_arr[0])

	var images: Array[Image] = []
	for z in range(depth):
		var start := offset + z * slice_bytes
		var end := start + slice_bytes
		var slice_buf := body.slice(start, end)
		var img := _create_image_from_bytes(slice_buf, width, height, dtype)
		if img == null:
			push_error("VolumetricData.set_from_bytes: failed to create image for slice %d" % z)
			return false
		images.append(img)

	var tex := ImageTexture3D.new()
	tex.create(width, height, depth, images[0].get_format(), false, images)
	_texture = tex
	data_ready.emit()
	return true
