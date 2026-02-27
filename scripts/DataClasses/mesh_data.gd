## Mesh-specific data container.
## Stores vertices, indices, normals and can produce an ArrayMesh.
class_name MeshData
extends Data

var vertices: PackedFloat32Array
var indices: PackedInt32Array
var normals: PackedFloat32Array
var flip_normals: bool = false

var _cached_mesh: ArrayMesh = null


func is_valid() -> bool:
	return vertices.size() > 0 and indices.size() > 0


## Returns a built ArrayMesh (cached after first call).
func get_data() -> ArrayMesh:
	if _cached_mesh == null and is_valid():
		_cached_mesh = MeshUtils.build_mesh(to_dict())
	return _cached_mesh


## Set data from a dictionary (as received from network or loaders).
## Expects {"vertices": [...], "indices": [...], "normals": [...]}
func set_from_dict(data: Dictionary) -> void:
	var v = data.get("vertices", PackedFloat32Array())
	var i = data.get("indices", PackedInt32Array())
	var n = data.get("normals", PackedFloat32Array())

	# Handle both flat arrays and typed arrays
	if typeof(v) == TYPE_PACKED_VECTOR3_ARRAY:
		vertices = MeshUtils.flatten_vector3(v)
	elif v is Array:
		vertices = PackedFloat32Array(v)
	else:
		vertices = v

	if i is Array:
		indices = PackedInt32Array(i)
	else:
		indices = i

	if typeof(n) == TYPE_PACKED_VECTOR3_ARRAY:
		normals = MeshUtils.flatten_vector3(n)
	elif n is Array:
		normals = PackedFloat32Array(n)
	else:
		normals = n

	_cached_mesh = null
	data_ready.emit()


## Export as a dictionary (for network transmission).
func to_dict() -> Dictionary:
	return {
		"vertices": vertices,
		"indices": indices,
		"normals": normals
	}


func clear() -> void:
	vertices = PackedFloat32Array()
	indices = PackedInt32Array()
	normals = PackedFloat32Array()
	_cached_mesh = null
