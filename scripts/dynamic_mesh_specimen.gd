extends "res://scripts/mesh_specimen.gd"

var mqtt_client = null
	
	
func _enter_tree() -> void:
	super()
	mqtt_client = get_tree().get_root().find_child("MQTT", true, false)
	mqtt_client.subscribe("python/processing_responses")
	mqtt_client.connect("received_message", _on_mqtt_message_received)
	
	test_request()
	
	
func test_request():
	send_processing_request('sphere')

func send_processing_request(function_name, args=null, kwargs=null):
	if args == null:
		args = []
	
	if kwargs == null:
		kwargs = {}
	
	var request_data = {
		'function_name': function_name,
		'args': args,
		'kwargs': kwargs
	}
	mqtt_client.publish("godot/processing_requests", JSON.stringify(request_data))

func _on_mqtt_message_received(topic, message):
	if multiplayer.get_unique_id() != 1:
		return
	
	var result_data = JSON.parse_string(message)
	
	# Handle the received mesh data
	var mesh = ArrayMesh.new()

	var verts = []
	for p in result_data["vertices"]:
		verts.append(Vector3(p[0], p[1], p[2]))

	var idxs = result_data["indices"]
	
	#var max_idx = 0
	#for i in idxs:
		#if i >= verts.size():
			#push_error("Bad index: " + str(i))
		#max_idx = max(max_idx, i)
	#print("Max index:", max_idx, "Vertex count:", verts.size())

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(idxs)

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY

	if specimen_scene:
		specimen_scene.queue_free()
	specimen_scene = mesh_instance
	set_pickable.rpc(make_pickable(mesh_instance))
