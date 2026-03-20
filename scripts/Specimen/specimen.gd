## Base specimen class.
## Handles UI viewport setup, story text, and optional pipeline integration.
class_name Specimen
extends Node3D

enum ScaleMode {TABLE, WORLD}
@export var display_name: String
@export var thumbnail: Texture2D
@export var scale_mode: ScaleMode = ScaleMode.TABLE
@export var ui: PackedScene
@export var enabled: bool = true
@export_multiline var story_text: Array[String]

## Optional pipeline for data loading (can be configured in editor via SpecimenDef).
@export var pipeline: Pipeline

var ui_instance: Control


func _enter_tree() -> void:
	var specimen_viewport = $/root/Main/SpecimenUIViewport
	var story_ui_viewport = $/root/Main/StoryUIViewport

	if ui and specimen_viewport:
		specimen_viewport.scene = ui
		ui_instance = specimen_viewport.get_scene_instance()

	if story_ui_viewport:
		var story_ui = story_ui_viewport.get_scene_instance()
		if story_ui and "story" in story_ui:
			if story_text:
				story_ui.story = story_text
			else:
				story_ui.story = PackedStringArray()
		elif story_ui:
			push_warning("StoryUI instance found but has no 'story' property: %s" % story_ui.get_class())
		else:
			# StoryUI not instantiated yet - this is OK, it might not have a scene set
			pass

	# If a pipeline is configured, wire it up and run it
	if pipeline:
		pipeline.add_pickable.connect(_on_pipeline_pickable)
		pipeline.pipeline_error.connect(func(e): push_error("Specimen pipeline: " + e))
		pipeline.run_pipeline()


func _on_pipeline_pickable(pickable: Node3D) -> void:
	add_child(pickable)
