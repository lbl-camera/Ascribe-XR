extends Node3D

@export var pipeline: Pipeline

var source: DataSource 
var loader: Loader
var pickable: ScalableMultiplayerPickable


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	source = pipeline.data_source
	loader = pipeline.loader
	pickable = pipeline.run_pipeline()
	
	add_child(pickable)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
