@tool
class_name LerpPositionPickable
extends "res://addons/godot-xr-tools/objects/pickable.gd"


## Pickable with a position-only variant of the LERP ranged-grab.
##
## With [member lerp_position_only] enabled and Ranged Grab Method set to
## Lerp, a ranged grab flies the object to the hand while preserving the
## rotation it had at grab time (relative to the hand), instead of also
## slerping its rotation to match the hand. Once held, the object still
## rotates with hand movement — it just never does the initial rotation snap.


## If true, ranged Lerp grabs only lerp position, keeping the object's rotation.
@export var lerp_position_only : bool = true


func pick_up(by: Node3D) -> void:
	var was_picked_up := is_picked_up()
	super.pick_up(by)

	# Only adjust fresh primary ranged-lerp grabs
	if not lerp_position_only or was_picked_up:
		return
	if not is_instance_valid(_grab_driver) or not _grab_driver.primary:
		return
	if _grab_driver.state != XRToolsGrabDriver.GrabState.LERP:
		return

	# Grab-point grabs define their own transform; leave those alone
	var grab := _grab_driver.primary
	if grab.by != by or grab.point:
		return

	# Rebuild the grab transform so the driver's destination keeps the
	# object's current rotation while its origin moves to the hand.
	var hand := by.global_transform
	var desired := Transform3D(global_transform.basis, hand.origin)
	grab.transform = (hand.affine_inverse() * desired).affine_inverse()
