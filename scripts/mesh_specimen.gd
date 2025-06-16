extends Specimen

var stl_importer = preload("res://tools/stl_importer.gd")
@export_file("*.stl", "*.fbx") var loading_file: String

var specimen_scene: Node3D
var specimen_collision: CollisionShape3D
var specimen_base_scale: float = 1
static var TABLE_SIZE: float   = 1


func _ready():
	if loading_file:
		_on_file_dialog_file_selected(loading_file)
		ui_instance.get_node("%FileDialog").hide()


#if OS.is_debug_build():
#_on_file_dialog_file_selected(r"C:\Users\rp\Documents\vr-start\skullandmore.stl")

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
		var child_bounds: AABB = get_node_aabb(child, false)
		if bounds.size == Vector3.ZERO:
			bounds = child_bounds
		else:
			bounds = bounds.merge(child_bounds)

	if !exclude_top_level_transform:
		bounds = node.transform * bounds

	return bounds


func _enter_tree() -> void:
	super._enter_tree()
	ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)
	ui_instance.get_node("%Scale").value_changed.connect(_on_scale_value_changed)
	ui_instance.get_node("%MaterialList").item_selected.connect(_on_materiallist_item_selected)


func _process(delta: float) -> void:
	process_mesh_load()


func process_mesh_load() -> void:
	if not loading_file:
		return

	var progress    = []
	var status: int = ResourceLoader.load_threaded_get_status(loading_file, progress)
	ui_instance.get_node("%ProgressBar").value = progress[0]
	if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		loading_file = ""
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		var mesh_scene: PackedScene = ResourceLoader.load_threaded_get(loading_file)
		if specimen_scene:
			specimen_scene.queue_free()
		make_pickable(mesh_scene.instantiate())
		loading_file = ""
		ui_instance.get_node("%LoadingLayer").hide()
		ui_instance.get_node("%SettingsLayer").show()


func _on_file_dialog_file_selected(path: String) -> void:
	var extension: String = path.get_extension()
	if extension in ['fbx']:
		ui_instance.get_node("LoadingLayer").show()
		ResourceLoader.load_threaded_request(path)
		loading_file = path
	elif extension == 'stl':
		var mesh          = stl_importer.new().import(path)
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		make_pickable(mesh_instance)
		ui_instance.get_node("%SettingsLayer").show()
		ui_instance.get_node("%MaterialMenu").show()


func make_pickable(node: Node3D) -> Node3D:
	var collision: CollisionShape3D         = CollisionShape3D.new()
	var pickable: MultiplayerPickableObject = MultiplayerPickableObject.new()
	pickable.add_child(node)
	pickable.add_child(collision)
	pickable.ranged_grab_method = XRToolsPickable.RangedMethod.LERP
	pickable.second_hand_grab = XRToolsPickable.SecondHandGrab.SWAP
	pickable.ranged_grab_speed = 10
	pickable.freeze = true
	pickable.set_collision_layer_value(1, false)
	pickable.set_collision_layer_value(3, true)
	for i in [1, 2, 3]:
		pickable.set_collision_mask_value(i, true)

	add_child(pickable)
	specimen_scene = node
	specimen_collision = collision

	var bounds = get_node_aabb(node)
	var base   = bounds.get_center()-Vector3(0, bounds.position.y/2, 0)
	collision.make_convex_from_siblings()
	specimen_base_scale = TABLE_SIZE/bounds.get_longest_axis_size()
	node.scale *= specimen_base_scale
	node.position -= base/bounds.get_longest_axis_size()
	collision.position -= base/bounds.get_longest_axis_size()
	collision.scale *= specimen_base_scale

	return pickable


func _on_scale_value_changed(value: float) -> void:
	if specimen_scene:
		specimen_scene.scale = specimen_base_scale * value * Vector3.ONE
		specimen_collision.scale = specimen_base_scale * value * Vector3.ONE


func _on_materiallist_item_selected(index: int):
	var material_list: ItemList = ui_instance.get_node("%MaterialList")
	var material_name: String   = material_list.get_item_text(index)
	set_shader(material_name)


func set_shader(material_name: String = "glass"):
	var shader                   = load("res://shaders/" + material_name.to_lower() + ".gdshader")
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	specimen_scene.set_surface_override_material(0, material)
