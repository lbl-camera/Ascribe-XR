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
var _story_instance: Control
var _is_active: bool = false


func _enter_tree() -> void:
	# Start disabled — SceneManager will call activate() to enable processing.
	process_mode = Node.PROCESS_MODE_DISABLED
	# If a pipeline is configured, wire it up and run it.
	# Pipelines run regardless of active state so data is ready when we activate.
	if pipeline:
		pipeline.add_pickable.connect(_on_pipeline_pickable)
		pipeline.pipeline_error.connect(func(e): push_error("Specimen pipeline: " + e))
		pipeline.run_pipeline()


## Called by SceneManager when this specimen becomes active.
## Spawns the per-specimen UI and story panels into MenuManager slots.
## Sets process_mode back to INHERIT so physics/pickables resume.
func activate() -> void:
	if _is_active:
		return
	_is_active = true
	process_mode = Node.PROCESS_MODE_INHERIT

	if ui:
		ui_instance = ui.instantiate()
		MenuManager.show_menu(ui_instance, {
			"slot": "specimen",
			"screen_size": Vector2(3, 1.68),
			"viewport_size": Vector2(1152, 648),
			"distance": 2.5,
		})

	if story_text and story_text.size() > 0:
		var story_scene = preload("res://scenes/UI/story_ui.tscn")
		_story_instance = story_scene.instantiate()
		_story_instance.story = story_text
		MenuManager.show_menu(_story_instance, {
			"slot": "story",
			"screen_size": Vector2(3, 1.68),
			"viewport_size": Vector2(1152, 648),
			"distance": 1.5,
			"offset": Vector2(2.5, 0),
		})


## Called by SceneManager when this specimen is no longer active.
## Closes the menus owned by this specimen and freezes the subtree.
func deactivate() -> void:
	if not _is_active:
		return
	_is_active = false
	# MenuManager.show_menu reuses slots, so a new active will overwrite these
	# slots. The explicit close is for the case where this specimen is being
	# removed without another taking over.
	if ui_instance:
		MenuManager.close_menu("specimen")
	if _story_instance:
		MenuManager.close_menu("story")
	ui_instance = null
	_story_instance = null
	process_mode = Node.PROCESS_MODE_DISABLED


func _on_pipeline_pickable(pickable: Node3D) -> void:
	add_child(pickable)
