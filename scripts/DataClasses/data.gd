## Base data container interface.
## Subclasses represent specific data types (mesh, volumetric, etc.)
class_name Data
extends RefCounted

## Emitted when data is ready for use
signal data_ready

## Emitted on error
signal load_failed(error: String)

## Returns true if data is loaded and valid
func is_valid() -> bool:
	return false

## Returns the data in a format suitable for the specimen
func get_data() -> Variant:
	return null

## Clears loaded data and frees resources
func clear() -> void:
	pass
