extends Panel

var room_scenes = {
	"lab": preload("res://scenes/Rooms/sci-fi_lab.tscn"),
	"passthrough": preload("res://scenes/Rooms/passthrough.tscn"),
	"black": preload("res://scenes/Rooms/black.tscn"),
	}


func _set_room_scene(room_name: String) -> void:
	SceneManager.set_room_scene(room_name)
