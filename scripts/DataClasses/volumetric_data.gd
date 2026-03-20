## Volumetric data container.
## Stores a 3D texture for volume rendering.
class_name VolumetricData
extends Data

var _texture: Texture3D
var _dimensions: Vector3i


func is_valid() -> bool:
	return _texture != null


func get_data() -> Texture3D:
	return _texture


func get_dimensions() -> Vector3i:
	return _dimensions


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


func clear() -> void:
	_texture = null
	_dimensions = Vector3i.ZERO
