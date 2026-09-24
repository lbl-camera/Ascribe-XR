@tool
class_name LerpPositionPickable
extends "res://addons/godot-xr-tools/objects/pickable.gd"


## Pickable whose ranged grab can preserve the object's orientation.
##
## With [member preserve_orientation] enabled, a ranged grab (Lerp or Snap)
## brings the object to the hand while keeping the world rotation it had at
## grab time, instead of rotating it to match the hand. Once held, the object
## still rotates with hand movement — it just never does the initial rotation
## snap. Disable for flat things (e.g. Viewport2Din3D panels) that should turn
## to face the user.


## If true, ranged grabs move the object to the hand without changing its rotation.
@export var preserve_orientation : bool = true


func pick_up(by: Node3D) -> void:
	var was_picked_up := is_picked_up()
	# Capture before super: a snap driver may move us during pick_up
	var start_basis := global_transform.basis
	super.pick_up(by)

	# Only adjust fresh primary ranged grabs
	if not preserve_orientation or was_picked_up or not by.get("picked_up_ranged"):
		return
	if not is_instance_valid(_grab_driver) or not _grab_driver.primary:
		return

	# Grab-point grabs define their own transform; leave those alone
	var grab := _grab_driver.primary
	if grab.by != by or grab.point:
		return

	# Rebuild the grab transform so the driver's destination keeps the
	# object's current rotation while its origin moves to the hand.
	var hand := by.global_transform
	var desired := Transform3D(start_basis, hand.origin)
	grab.transform = (hand.affine_inverse() * desired).affine_inverse()

	# Snap drivers were already placed using the old grab transform
	if _grab_driver.state == XRToolsGrabDriver.GrabState.SNAP:
		_grab_driver.global_transform = desired
