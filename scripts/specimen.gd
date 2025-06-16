# todo: give this an icon
#@icon()
class_name Specimen
extends Node3D

enum ScaleMode {TABLE, WORLD}
@export var display_name: String
@export var thumbnail: Texture2D
@export var scale_mode: ScaleMode = ScaleMode.TABLE
@export var ui: PackedScene

@export_multiline var story_text: Array[String]

var ui_instance: Control


func _enter_tree() -> void:
	if ui:
		ui_instance = $/root/Main/SpecimenUIViewport.get_scene_instance()
