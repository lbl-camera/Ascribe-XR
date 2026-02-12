extends Node3D

@export var source: FileSource
var pipeline: Pipeline
var loader: Loader
var pickable: ScalableMultiplayerPickable


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pipeline = Pipeline.new()
	pickable = pipeline.run_pipeline(source)
	print(pickable)
	add_child(pickable)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
