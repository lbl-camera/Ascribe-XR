## Synchronous (blocking) loader.
## Handles STL, FBX file loading and dictionary-based data (from network).
class_name SyncronousLoader
extends Loader

var stl_importer = preload("res://tools/stl_importer.gd")


func load_data(source_data: Variant, target: Data) -> void:
	if source_data is String:
		_load_from_file(source_data, target)
	elif source_data is Dictionary:
		_load_from_dict(source_data, target)
	else:
		load_error.emit("SyncronousLoader: Unknown source data type: %s" % typeof(source_data))


func _load_from_file(path: String, target: Data) -> void:
	var ext := path.get_extension().to_lower()

	if target is MeshData:
		match ext:
			"stl":
				_load_stl(path, target)
			"fbx":
				_load_fbx(path, target)
			_:
				load_error.emit("SyncronousLoader: Unsupported mesh format: %s" % ext)
	elif target is VolumetricData:
		match ext:
			"bin":
				_load_bin(path, target)
			"zip":
				_load_zip(path, target)
			_:
				load_error.emit("SyncronousLoader: Unsupported volume format: %s" % ext)
	else:
		load_error.emit("SyncronousLoader: Unknown target data type")


func _load_stl(path: String, target: MeshData) -> void:
	var importer = stl_importer.new()
	var mesh_data = importer.import(path, target.flip_normals)
	if mesh_data == null or mesh_data.is_empty():
		load_error.emit("STL import failed: %s" % path)
		return
	target.set_from_dict(mesh_data)
	load_complete.emit(target)


func _load_fbx(path: String, target: MeshData) -> void:
	var doc = FBXDocument.new()
	var state = FBXState.new()
	var err = doc.append_from_file(path, state)
	if err != OK:
		load_error.emit("Failed to parse FBX: %s" % err)
		return
	var scene_root = doc.generate_scene(state)
	if not scene_root:
		load_error.emit("FBXDocument.generate_scene returned null")
		return
	var mesh = MeshUtils.combine_meshes_from_node(scene_root)
	var data = MeshUtils.extract_mesh_data(mesh)
	scene_root.queue_free()
	target.set_from_dict(data)
	load_complete.emit(target)


func _load_from_dict(data: Dictionary, target: Data) -> void:
	if target is MeshData:
		target.set_from_dict(data)
		load_complete.emit(target)
	else:
		load_error.emit("SyncronousLoader: Cannot load dict into %s" % target.get_class())


func _load_bin(path: String, target: VolumetricData) -> void:
	# TODO: Make dimensions configurable
	var shape := Vector3i(256, 256, 10)
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		load_error.emit("Cannot open file: %s" % path)
		return
	var data := file.get_buffer(file.get_length())
	file.close()

	var images: Array[Image] = []
	var frame_size := shape.x * shape.y
	for z in range(shape.z):
		var start := z * frame_size
		var img := Image.create_from_data(shape.x, shape.y, false, Image.FORMAT_L8, data.slice(start, start + frame_size))
		images.append(img)

	target.set_from_images(images, shape)
	load_complete.emit(target)


func _load_zip(path: String, target: VolumetricData) -> void:
	var texture: ZippedImageArchiveRFTexture3D = ZippedImageArchiveRFTexture3D.new()
	var archive = ZippedImageArchive_RF_3D.new()
	archive.zip_file = path
	texture.archive = archive
	# ZippedImageArchiveRFTexture3D handles lazy loading internally
	# We set it directly; dimensions come from the archive
	target._texture = texture
	target.data_ready.emit()
	load_complete.emit(target)
