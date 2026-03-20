## Threaded (background) loader.
## Uses Godot's ResourceLoader for threaded loading (OBJ, etc.)
## and falls back to SyncronousLoader on a Thread for other formats.
class_name ThreadedLoader
extends Loader

var _sync_loader: SyncronousLoader
var _thread: Thread
var _polling_path: String = ""
var _polling_target: Data = null
var _thread_result: Data = null  # Set by background thread, consumed by poll()
var _thread_error: String = ""   # Set by background thread, consumed by poll()
var _thread_done: bool = false


func _init() -> void:
	_sync_loader = SyncronousLoader.new()
	# Connect with DEFERRED flag so signals from background thread
	# queue onto the main thread — but we also handle via poll() for safety
	_sync_loader.load_complete.connect(_on_thread_complete)
	_sync_loader.load_error.connect(_on_thread_error)


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


## Must be called each frame to poll loading status.
## Returns true when loading is complete (or failed).
func poll() -> bool:
	# Check background thread completion first
	if _thread_done:
		_thread_done = false
		if _thread:
			_thread.wait_to_finish()
			_thread = null
		if _thread_error != "":
			load_error.emit(_thread_error)
			_thread_error = ""
		elif _thread_result != null:
			var result = _thread_result
			_thread_result = null
			load_complete.emit(result)
		return true

	# Poll Godot's ResourceLoader (OBJ path)
	if _polling_path != "":
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
		return false

	# Nothing pending
	if _thread and not _thread.is_started():
		return true
	if _thread:
		return false  # Thread still running
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


func _on_thread_complete(data: Data) -> void:
	# Called from background thread — store result for main thread poll()
	_thread_result = data
	_thread_done = true


func _on_thread_error(error: String) -> void:
	# Called from background thread — store error for main thread poll()
	_thread_error = error
	_thread_done = true


func _threaded_load(source_data: Variant, target: Data) -> void:
	_sync_loader.load_data(source_data, target)


## Clean up thread if still running.
func cleanup() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
