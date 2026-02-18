class_name Pipeline
extends Resource

@export var specimen_def: SpecimenDef

signal add_pickable(pickable)
var pickables: Array[MultiplayerPickable]
var specimen_base_scale: float = 1
static var TABLE_SIZE: float   = 1
var loader: Loader
var data_source: DataSource
var data: Data
var PICKABLE_SCENE = preload("res://scenes/pickable/scalable_multiplayer_pickable.tscn")

# Called when the node enters the scene tree for the first time.




# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
# from specimens, run the pipeline
# when running the pipeline 
# the specimen has a pipeline
# pipeline has a data source, data loader, and type

# run pipeline needs to load the specimen from the source
# from there we can generate pickables
# when a pickable is made, signal goes out to the specimen to add it to the tree
func run_pipeline():
	if !specimen_def:
		print("no specimen def when running pipeline")
		return
	data_source = specimen_def.source
	loader = specimen_def.loader
	# loader = ThreadedLoader.new(source.get_file_path())
	var mesh_data: Dictionary = loader.load_data(data_source)
	if mesh_data is Dictionary:
		data = MeshData.new()
		data = data.set_data(mesh_data)
	var mesh = data_source.build_mesh(mesh_data)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY
	var pickable = make_pickable(mesh_instance)
	return pickable
	
	
# specimen can have a data source (file source for right now)
# in the context a file describing a mesh
# in FileResource, read and parse the file, you will probably get a mesh array (file source)
# loader.load will unpack the resource, gives opportunity for changing how unpacking is executed
# from there, get the return value from the source
# different routes to deal with different returned types: 
# that mesh gets sent to make pickable
	
## Return the [AABB] of the node.
func get_node_aabb(node: Node, exclude_top_level_transform: bool = true) -> AABB:
	var bounds: AABB = AABB()

	# Do not include children that is queued for deletion
	if node.is_queued_for_deletion():
		return bounds

	# Get the aabb of the visual instance
	if node is VisualInstance3D:
		bounds = node.get_aabb();

	# Recurse through all children
	for child in node.get_children():
		if "transform" not in child:
			continue
		var child_bounds: AABB = get_node_aabb(child, false)
		if bounds.size == Vector3.ZERO:
			bounds = child_bounds
		else:
			bounds = bounds.merge(child_bounds)

	if !exclude_top_level_transform:
		bounds = node.transform * bounds

	return bounds

func make_pickable(node: Node3D):
	var collision: CollisionShape3D         = CollisionShape3D.new()
	var pickable = PICKABLE_SCENE.instantiate()
	pickable.add_child(node)
	pickable.add_child(collision)

	#specimen_scene = node
	#specimen_collision = collision

	var bounds = get_node_aabb(node)
	var base   = bounds.get_center()-Vector3(0, bounds.position.y/2, 0)
	collision.make_convex_from_siblings()
	specimen_base_scale = TABLE_SIZE/bounds.get_longest_axis_size()
	node.scale *= specimen_base_scale
	node.position -= base/bounds.get_longest_axis_size()
	collision.position -= base/bounds.get_longest_axis_size()
	collision.scale *= specimen_base_scale
	pickables.append(pickable)
	add_pickable.emit(pickable)
	return pickable
	
