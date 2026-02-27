## Base data source interface.
## Represents WHERE data comes from (file, network, embedded, etc.)
class_name DataSource
extends Resource

## Emitted when raw data is available from the source.
signal data_available(raw_data: Variant)

## Emitted on progress (0.0 to 1.0)
signal progress_updated(progress: float)

## Emitted on error
signal source_error(error: String)

## Returns true if this source is ready to provide data.
func is_available() -> bool:
	return false

## Begin fetching data from the source (may be async).
func fetch() -> void:
	push_error("DataSource.fetch() must be overridden")

## Cancel an in-progress fetch.
func cancel() -> void:
	pass
