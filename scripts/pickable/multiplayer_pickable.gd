extends "res://addons/godot-xr-tools/objects/pickable.gd"
class_name MultiplayerPickable

# these are configured as "Watch" in the MultiplayerSynchronizer
@export var replicated_position: Vector3
@export var replicated_rotation: Vector3
@export var replicated_linear_velocity: Vector3
@export var replicated_angular_velocity: Vector3

var unfreeze_for_grab: bool = false


func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
	# Synchronizing the physics values directly causes problems since you can't
	# directly update physics values outside of _integrate_forces. This is
	# an attempt to resolve that problem while still being able to use
	# MultiplayerSynchronizer to replicate the values.

	# The object owner makes shadow copies of the physics values.
	# These shadow copies get synchronized by the MultiplyaerSynchronizer
	# The client copies the synchronized shadow values into the
	# actual physics properties inside integrate_forces
	if is_multiplayer_authority():
		replicated_position = position
		replicated_rotation = rotation
		replicated_linear_velocity = linear_velocity
		replicated_angular_velocity = angular_velocity
	else:
		position = replicated_position
		rotation = replicated_rotation
		linear_velocity = replicated_linear_velocity
		angular_velocity = replicated_angular_velocity




func _physics_process(_delta: float) -> void:
	if is_picked_up() and is_multiplayer_authority():
		replicated_position = position
		replicated_rotation = rotation
		replicated_linear_velocity = linear_velocity
		replicated_angular_velocity = angular_velocity

@rpc("any_peer", "call_local", "reliable")
func take_authority(_pickable):
	if multiplayer.get_remote_sender_id() != 1:
		set_multiplayer_authority(multiplayer.get_remote_sender_id())
		print("authority of ", self, " given to ", multiplayer.get_remote_sender_id(), " on ", multiplayer.get_unique_id())

	# frozen objects need to be unfrozen on non-authority peers for movement to propagate
	if unfreeze_for_grab and multiplayer.get_unique_id() != multiplayer.get_remote_sender_id():
		freeze = false

@rpc("any_peer", "call_local", "reliable")
func surrender_authority(_pickable, _by):
	if unfreeze_for_grab:
		freeze = true

	if multiplayer.get_remote_sender_id() != 1:
		set_multiplayer_authority(1)
		print("authority of ", self, " surrendered")


func _ready():
	super()
	if freeze:
		unfreeze_for_grab = true
	picked_up.connect(take_authority.rpc)
	released.connect(surrender_authority.rpc)
