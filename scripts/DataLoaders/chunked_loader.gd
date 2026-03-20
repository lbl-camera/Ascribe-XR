## Chunked loader for progressive network loading.
## Works with RPCSource to assemble data from chunks.
## This loader doesn't do much parsing — the RPCSource handles accumulation.
## It just passes the completed dictionary to the target.
class_name ChunkedLoader
extends Loader

var _sync_loader: SyncronousLoader


func _init() -> void:
	_sync_loader = SyncronousLoader.new()
	_sync_loader.load_complete.connect(func(d): load_complete.emit(d))
	_sync_loader.load_error.connect(func(e): load_error.emit(e))


func load_data(source_data: Variant, target: Data) -> void:
	# source_data should be a completed Dictionary from RPCSource
	_sync_loader.load_data(source_data, target)
