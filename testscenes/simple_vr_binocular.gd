extends Node3D

func _process(delta):
	var joyv = $XROrigin3D/XRController3D.get_vector2("primary")
	$XROrigin3D/StudyObject.rotation_degrees += Vector3(joyv.y*delta*20, joyv.x*delta*20, 0.0)
	
func _on_xr_controller_3d_input_vector_2_changed(name, value):
	prints("vec2 thing", name, value)
