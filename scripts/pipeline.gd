## Orchestrates source → loader → data type.
## Wires signals between components for async data flow.
class_name Pipeline
extends Resource

signal pipeline_complete(data: Data)
signal pipeline_progress(progress: float)
signal pipeline_error(error: String)
signal add_pickable(pickable: Node3D)

@export var specimen_def: SpecimenDef

var _source: DataSource
var _loader: Loader
var _target: Data
var pickables: Array = []
var specimen_base_scale: float = 1
static var TABLE_SIZE: float = 1

var PICKABLE_SCENE = preload("res://scenes/pickable/scalable_multiplayer_pickable.tscn")


## Configure the pipeline with explicit components.
func configure(source: DataSource, loader: Loader, target: Data) -> Pipeline:
	_source = source
	_loader = loader
	_target = target
	_wire_signals()
	return self


## Run the pipeline using the SpecimenDef (if set) or pre-configured components.
func run_pipeline() -> Variant:
	if specimen_def:
		_source = specimen_def.source
		_loader = specimen_def.loader
		if _source is FileSource:
			# Determine target type from file extension
			var ext = _source.get_file_type()
			match ext:
				"stl", "fbx", "obj":
					_target = MeshData.new()
				"bin", "zip":
					_target = VolumetricData.new()
				_:
					pipeline_error.emit("Unknown file type: %s" % ext)
					return null
		elif _source is MQTTSource or _source is HTTPSource:
			_target = MeshData.new()
		else:
			_target = MeshData.new()
		_wire_signals()

	if _source == null or _loader == null or _target == null:
		pipeline_error.emit("Pipeline not configured: missing source, loader, or target")
		return null

	_source.fetch()
	return null


func _wire_signals() -> void:
	if _source.data_available.is_connected(_on_source_data):
		return
	_source.data_available.connect(_on_source_data)
	_source.progress_updated.connect(func(p): pipeline_progress.emit(p * 0.5))
	_source.source_error.connect(func(e): pipeline_error.emit("Source: " + e))

	_loader.load_complete.connect(_on_load_complete)
	_loader.load_progress.connect(func(p): pipeline_progress.emit(0.5 + p * 0.5))
	_loader.load_error.connect(func(e): pipeline_error.emit("Loader: " + e))


func _on_source_data(raw_data: Variant) -> void:
	_loader.load_data(raw_data, _target)


func _on_load_complete(data: Data) -> void:
	pipeline_complete.emit(data)
	if data is MeshData:
		_create_mesh_pickable(data)


func _create_mesh_pickable(mesh_data: MeshData) -> void:
	var mesh = mesh_data.get_data()
	if mesh == null:
		pipeline_error.emit("Failed to build mesh from data")
		return

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY
	var pickable = make_pickable(mesh_instance)
	return


func make_pickable(node: Node3D) -> Node3D:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var pickable = PICKABLE_SCENE.instantiate()
	pickable.add_child(node)
	pickable.add_child(collision)

	var bounds = MeshUtils.get_node_aabb(node)
	var base = bounds.get_center() - Vector3(0, bounds.position.y / 2, 0)
	collision.make_convex_from_siblings()
	specimen_base_scale = TABLE_SIZE / bounds.get_longest_axis_size()
	node.scale *= specimen_base_scale
	node.position -= base / bounds.get_longest_axis_size()
	collision.position -= base / bounds.get_longest_axis_size()
	collision.scale *= specimen_base_scale
	pickables.append(pickable)
	add_pickable.emit(pickable)
	return pickable


## Factory: file → mesh pipeline (always threaded to avoid UI freezes)
static func file_to_mesh(path: String) -> Pipeline:
	var pipeline := Pipeline.new()
	var source := FileSource.new(path)
	var loader := ThreadedLoader.new()
	var target := MeshData.new()
	return pipeline.configure(source, loader, target)


## Factory: file → volumetric pipeline
static func file_to_volume(path: String) -> Pipeline:
	var pipeline := Pipeline.new()
	var source := FileSource.new(path)
	var loader := SyncronousLoader.new()
	var target := VolumetricData.new()
	return pipeline.configure(source, loader, target)


## Factory: HTTP → mesh pipeline (Ascribe-Link server)
static func http_to_mesh(parent: Node, function_name: String, args: Array = [], kwargs: Dictionary = {}, base_url: String = "http://localhost:8000") -> Pipeline:
	var pipeline := Pipeline.new()
	var source := HTTPSource.new(base_url)
	source.setup(parent)
	source.set_request({
		"function_name": function_name,
		"args": args,
		"kwargs": kwargs
	})
	var loader := SyncronousLoader.new()
	var target := MeshData.new()
	return pipeline.configure(source, loader, target)


## Factory: MQTT → mesh pipeline (deprecated — use http_to_mesh instead)
static func mqtt_to_mesh(mqtt: Node, function_name: String, args: Array = [], kwargs: Dictionary = {}) -> Pipeline:
	push_warning("mqtt_to_mesh is deprecated — use http_to_mesh instead")
	var pipeline := Pipeline.new()
	var source := MQTTSource.new()
	source.setup(mqtt)
	source.set_request({
		"function_name": function_name,
		"args": args,
		"kwargs": kwargs
	})
	var loader := SyncronousLoader.new()
	var target := MeshData.new()
	return pipeline.configure(source, loader, target)
