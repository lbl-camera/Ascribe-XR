extends Loader
class_name ThreadedLoader

var loading_file: String
var data_source: DataSource

func _init( _loaded_file: String):

	loading_file = _loaded_file
	
	
func load_data(source: DataSource):
	var data = load_path(source.get_file_path)
	return data



func _process(delta: float) -> void:
	process_mesh_load()


func process_mesh_load() -> void:
	if not loading_file:
		return
	var data = null
	var progress    = []
	# give the thing youre trying to load, progress is an
	var status: int = ResourceLoader.load_threaded_get_status(loading_file, progress)
	ui_instance.get_node("%ProgressBar").value = progress[0]
	if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		loading_file = ""
		ui_instance.get_node("LoadingLayer").hide()
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		var mesh_resource = ResourceLoader.load_threaded_get(loading_file)
		if mesh_resource is ArrayMesh:
			data = data_source.extract_mesh_data(mesh_resource)
			# set_and_send_mesh(data)
		loading_file = ""
		ui_instance.get_node("LoadingLayer").hide()

		

func load_fbx(path:String):
	var doc = FBXDocument.new()
	var state = FBXState.new()  # or maybe FBXState if available
	var err = doc.append_from_file(path, state)
	if err != OK:
		push_error("Failed to parse FBX: %s" % err)
		return
	var scene_root = doc.generate_scene(state)
	if not scene_root:
		push_error("FBXDocument.generate_scene returned null")
		return

func load_path(path):
	var extension: String = path.get_extension()
	if extension == 'fbx':
		var scene = load_fbx(path)
		var mesh = data_source.combine_meshes_from_node(scene)
		var data = data_source.extract_mesh_data(mesh)
		return data
	elif extension == 'obj':
		ui_instance.get_node("LoadingLayer").show()
		ResourceLoader.load_threaded_request(path)
		loading_file = path
	elif extension == 'stl':
		var importer = stl_importer.new()
		var mesh_data = importer.import(path, false)
		return mesh_data
