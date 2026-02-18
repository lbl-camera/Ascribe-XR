extends Data
class_name MeshData

var flip_normals: bool = false # might need export as a resource

var data: Dictionary


func _ready() -> void:
	pass

func set_data(mesh_data):
	data = mesh_data
