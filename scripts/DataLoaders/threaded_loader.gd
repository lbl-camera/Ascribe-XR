## Threaded (background) loader.
## Uses Godot's ResourceLoader for threaded loading (OBJ, etc.)
## and falls back to SyncronousLoader on a Thread for other formats.
class_name ThreadedLoader
extends Loader

var _sync_loader: SyncronousLoader
var _thread: Thread
var _polling_path: String = ""
var _polling_target: Data = null


func _init() -> void:
	_sync_loader = SyncronousLoader.new()
	_sync_loader.load_complete.connect(func(d): load_complete.emit(d))
	_sync_loader.load_error.connect(func(e): load_error.emit(e))


func load_data(source_data: Variant, target: Data) -> void:
	if source_data is String:
		var ext: String = source_data.get_extension().to_lower()
		if ext == "obj":
			# Use Godot's built-in threaded resource loader
			ResourceLoader.load_threaded_request(source_data)
			_polling_path = source_data
			_polling_target = target
			return

	# For other formats, run sync loader on a background thread
	_thread = Thread.new()
	_thread.start(_threaded_load.bind(source_data, target))


## Must be called each frame to poll ResourceLoader status.
## Returns true when loading is complete (or failed).
func poll() -> bool:
	if _polling_path == "":
		return true

	var progress := []
	var status: int = ResourceLoader.load_threaded_get_status(_polling_path, progress)

	if progress.size() > 0:
		load_progress.emit(progress[0])

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		ResourceLoader.THREAD_LOAD_LOADED:
			var resource = ResourceLoader.load_threaded_get(_polling_path)
			_polling_path = ""
			_handle_loaded_resource(resource, _polling_target)
			_polling_target = null
			return true
		_:
			load_error.emit("Resource load failed for: %s" % _polling_path)
			_polling_path = ""
			_polling_target = null
			return true

	return true


func _handle_loaded_resource(resource: Variant, target: Data) -> void:
	if target is MeshData:
		var mesh: ArrayMesh = null
		if resource is PackedScene:
			var instance = resource.instantiate()
			mesh = MeshUtils.find_mesh_instance(instance)
			if mesh:
				var data = MeshUtils.extract_mesh_data(mesh)
				target.set_from_dict(data)
			instance.queue_free()
		elif resource is ArrayMesh:
			var data = MeshUtils.extract_mesh_data(resource)
			target.set_from_dict(data)
		else:
			load_error.emit("Unsupported resource type for mesh loading")
			return
		load_complete.emit(target)
	else:
		load_error.emit("ThreadedLoader: Cannot handle resource for this data type")


func _threaded_load(source_data: Variant, target: Data) -> void:
	_sync_loader.load_data(source_data, target)


## Clean up thread if still running.
func cleanup() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
