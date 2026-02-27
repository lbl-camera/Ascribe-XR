## RPC chunk-based data source.
## Receives mesh data in chunks over multiplayer RPC.
class_name RPCSource
extends DataSource

var _accumulated_data: Dictionary = {
	"vertices": PackedFloat32Array(),
	"indices": PackedInt32Array(),
	"normals": PackedFloat32Array()
}
var _expected_total: int = 0
var _received_count: int = 0


func is_available() -> bool:
	return true


func fetch() -> void:
	# RPC source is passive — data arrives via receive_chunk()
	pass


## Called from an RPC handler when a chunk arrives.
func receive_chunk(chunk: Variant, field: String, index: int, total: int, is_last: bool) -> void:
	_expected_total = total
	_received_count = index + 1
	_accumulated_data[field].append_array(chunk)

	progress_updated.emit(float(_received_count) / float(_expected_total))

	if is_last:
		var result = _accumulated_data.duplicate()
		_reset()
		data_available.emit(result)


func cancel() -> void:
	_reset()


func _reset() -> void:
	_accumulated_data = {
		"vertices": PackedFloat32Array(),
		"indices": PackedInt32Array(),
		"normals": PackedFloat32Array()
	}
	_expected_total = 0
	_received_count = 0
