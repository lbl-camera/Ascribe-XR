extends Node3D

@export var pipeline: Pipeline


func _ready() -> void:
	if pipeline:
		pipeline.pipeline_complete.connect(_on_complete)
		pipeline.pipeline_error.connect(_on_error)
		pipeline.add_pickable.connect(_on_pickable)
		pipeline.run_pipeline()
	else:
		push_error("PipelineTest: No pipeline assigned")


func _on_complete(data: Data) -> void:
	print("Pipeline complete: data valid = %s" % data.is_valid())


func _on_error(error: String) -> void:
	push_error("Pipeline error: %s" % error)


func _on_pickable(pickable: Node3D) -> void:
	add_child(pickable)
	print("Pickable added to scene")
