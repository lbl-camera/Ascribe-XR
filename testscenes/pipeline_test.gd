extends Node3D

@export var source: FileSource
var pipeline: Pipeline
var loader: Loader


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pipeline = Pipeline.new()
	pipeline.run_pipeline(source)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
