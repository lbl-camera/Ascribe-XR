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
	var specimen_viewport = $/root/Main/SpecimenUIViewport
	var story_ui_viewport = $/root/Main/StoryUIViewport
	
	if ui and specimen_viewport:
		specimen_viewport.scene = ui
		ui_instance = specimen_viewport.get_scene_instance()
	
	if story_ui_viewport:
		if story_text:
			story_ui_viewport.get_node("Viewport/StoryUI").story = story_text
		else:
			story_ui_viewport.get_node("Viewport/StoryUI").story = PackedStringArray()
