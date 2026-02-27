## Repository-based data source (future).
## Will fetch data from a centralized data repository.
class_name RepoSource
extends DataSource


func is_available() -> bool:
	return false


func fetch() -> void:
	source_error.emit("RepoSource: Not yet implemented")
