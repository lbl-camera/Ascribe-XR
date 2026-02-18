extends DataSource
class_name FileSource
@export_file("*.stl", "*.fbx") var loading_file: String



func set_file_path(new_path: String):
	loading_file = new_path
	
func get_file_path():
	return loading_file
