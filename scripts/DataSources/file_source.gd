## File-based data source.
## Provides a local file path to the loader for parsing.
class_name FileSource
extends DataSource

@export_file("*.stl", "*.fbx", "*.obj", "*.bin", "*.zip") var file_path: String


func _init(path: String = "") -> void:
	file_path = path


func is_available() -> bool:
	return file_path != "" and FileAccess.file_exists(file_path)


func get_file_type() -> String:
	return file_path.get_extension().to_lower()


func fetch() -> void:
	if not is_available():
		source_error.emit("File not found: %s" % file_path)
		return
	data_available.emit(file_path)
