extends Node3D

## Demo script showing how to use XRToolsScalablePickable

@onready var scalable_cube = %ScalableMultiplayerPickableObject

func _ready():
	# Connect to scaling signals for feedback
	if scalable_cube:
		scalable_cube.scaling_started.connect(_on_scaling_started)
		scalable_cube.scaling_ended.connect(_on_scaling_ended)
		scalable_cube.scaling_updated.connect(_on_scaling_updated)
		scalable_cube.picked_up.connect(_on_picked_up)
		scalable_cube.dropped.connect(_on_dropped)

func _on_scaling_started(pickable: ScalableMultiplayerPickable):
	print("Started scaling: %s" % pickable.name)
	# Optional: Add visual feedback like particle effects or sound

func _on_scaling_ended(pickable: ScalableMultiplayerPickable):
	print("Stopped scaling: %s (final scale: %.2f)" % [pickable.name, pickable.get_scale_factor()])
	# Optional: Save the final scale or trigger other effects

func _on_scaling_updated(pickable: ScalableMultiplayerPickable, scale_factor: float):
	# This fires every frame during scaling - use sparingly
	print("Scaling: %s to %.2fx" % [pickable.name, scale_factor])

func _on_picked_up(pickable: XRToolsPickable):
	print("Picked up: %s" % pickable.name)

func _on_dropped(pickable: XRToolsPickable):
	print("Dropped: %s" % pickable.name)
