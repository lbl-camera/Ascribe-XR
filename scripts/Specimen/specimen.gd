## Base specimen class.
## Handles UI display via MenuManager, story text, and optional pipeline integration.
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
	# Specimen UI via MenuManager
	if ui:
		ui_instance = ui.instantiate()
		MenuManager.show_menu(ui_instance, {
			"slot": "specimen",
			"screen_size": Vector2(3, 1.68),
			"viewport_size": Vector2(1152, 648),
			"distance": 2.5,
		})

	# Story text via MenuManager (separate slot)
	if story_text and story_text.size() > 0:
		var story_scene = preload("res://scenes/UI/story_ui.tscn")
		var story_instance = story_scene.instantiate()
		story_instance.story = story_text
		MenuManager.show_menu(story_instance, {
			"slot": "story",
			"screen_size": Vector2(3, 1.68),
			"viewport_size": Vector2(1152, 648),
			"distance": 2.5,
			"offset": Vector2(2.5, 0),  # Spawn to the right of the specimen menu
		})

	# If a pipeline is configured, wire it up and run it
	if pipeline:
		pipeline.add_pickable.connect(_on_pipeline_pickable)
		pipeline.pipeline_error.connect(func(e): push_error("Specimen pipeline: " + e))
		pipeline.run_pipeline()


func _on_pipeline_pickable(pickable: Node3D) -> void:
	add_child(pickable)
