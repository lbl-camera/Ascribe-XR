extends Panel

var room_scenes = {
	"lab": preload("res://scenes/sci-fi_lab.tscn"),
	"passthrough": preload("res://scenes/passthrough.tscn"),
	"black": preload("res://scenes/black.tscn"),
	}


func _set_room_scene(room_name: String) -> void:
	Ascribemain.set_room_scene(room_name)
