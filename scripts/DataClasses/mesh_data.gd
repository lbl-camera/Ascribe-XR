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
		_cached_mesh = MeshUtils.build_mesh(to_dict(), flip_normals)
	return _cached_mesh


## Set data from a dictionary (as received from network or loaders).
## Supports both legacy format {"vertices": [...], "indices": [...]}
## and typed format {"type": "mesh", "vertices": [...], "indices": [...]}
func set_from_dict(data: Dictionary) -> void:
	# Handle typed format (ignore 'type' field, it's just for routing)
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


## Set data from the binary envelope body.
##
## `preamble` is the dict returned by `BinaryEnvelope.parse`.
## `body` is the full response body (including the 4-byte length prefix and JSON preamble).
## `offset` is the byte position where the data blocks start (`preamble.offset` from the parser).
##
## Block order (per ascribe-link envelope v1): vertices (float32), indices (uint32),
## normals (float32). Counts of 0 omit the block.
##
## Returns true on success, false on error (malformed preamble or body-too-short).
func set_from_bytes(preamble: Dictionary, body: PackedByteArray, offset: int) -> bool:
	if preamble.get("type", "") != "mesh":
		push_error("MeshData.set_from_bytes: preamble.type is not 'mesh'")
		return false

	var vc: int = int(preamble.get("vertex_count", 0))
	var ic: int = int(preamble.get("index_count", 0))
	var nc: int = int(preamble.get("normal_count", 0))

	var vertex_bytes := vc * 3 * 4
	var index_bytes := ic * 4
	var normal_bytes := nc * 3 * 4
	var required := offset + vertex_bytes + index_bytes + normal_bytes
	if body.size() < required:
		push_error("MeshData.set_from_bytes: body too short (need %d, got %d)" % [required, body.size()])
		return false

	var cursor := offset
	if vc > 0:
		vertices = body.slice(cursor, cursor + vertex_bytes).to_float32_array()
	else:
		vertices = PackedFloat32Array()
	cursor += vertex_bytes

	if ic > 0:
		indices = body.slice(cursor, cursor + index_bytes).to_int32_array()
	else:
		indices = PackedInt32Array()
	cursor += index_bytes

	if nc > 0:
		normals = body.slice(cursor, cursor + normal_bytes).to_float32_array()
	else:
		normals = PackedFloat32Array()

	_cached_mesh = null
	data_ready.emit()
	return true
