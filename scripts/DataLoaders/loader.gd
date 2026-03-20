## Base loader strategy interface.
## Defines HOW data is loaded (sync, threaded, chunked).
class_name Loader
extends Resource

signal load_complete(data: Data)
signal load_progress(progress: float)
signal load_error(error: String)

## Parse raw data from source into a typed data container.
## Subclasses implement format-specific parsing.
func load_data(source_data: Variant, target: Data) -> void:
	push_error("Loader.load_data() must be overridden")
