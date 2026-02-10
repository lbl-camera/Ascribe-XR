extends DataSource
class_name FileSource
@export_file("*.stl", "*.fbx") var loading_file: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_path(new_path: String):
	loading_file = new_path
	
func get_file_path():
	return loading_file
