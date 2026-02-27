## Embedded/bundled data source.
## References data files bundled with the application (res:// paths).
class_name EmbeddedSource
extends DataSource

@export var data_path: String


func _init(path: String = "") -> void:
	data_path = path


func is_available() -> bool:
	var resolved = _resolve_path()
	return ResourceLoader.exists(resolved) or FileAccess.file_exists(resolved)


func fetch() -> void:
	var resolved = _resolve_path()
	if not is_available():
		source_error.emit("Embedded data not found: %s" % data_path)
		return
	data_available.emit(resolved)


func _resolve_path() -> String:
	if data_path.begins_with("res://") or data_path.begins_with("user://"):
		return data_path
	return "res://data/" + data_path
