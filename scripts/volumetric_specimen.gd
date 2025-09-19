@tool
extends Specimen

var volume_layered: VolumeLayers
var mat: ShaderMaterial

func _ready():
	volume_layered = get_node("%VolumeLayeredShader")
	var mesh_inst = volume_layered.get_child(0, true)
	mat = mesh_inst.get_surface_override_material(0)
	
	if ui_instance:
		for name in ['gamma', 'opacity', 'color_scalar', 'max_steps', 'step_size', 'zoom']:
			var slider = ui_instance.get_node("%"+name+"Slider")
			slider.value_changed.connect(update_shader.bind(name))
			slider.value = volume_layered[name]
		ui_instance.get_node("%GradientItemList").colormap_selected.connect(update_shader_colormap)
		
		ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)
		
		if volume_layered.texture:
			ui_instance.get_node("%FileDialogLayer").hide()
			ui_instance.get_node("%SettingsLayer").show()
			enable_pickables()
	
	#_on_file_dialog_file_selected(r"C:\Users\rp\Documents\vr-start\specimen_data\cthead-8bit.zip")
			
func enable_pickables():
	$ScalableMultiplayerPickableObject.show()
	$MultiplayerPickable.show()
	$ScalableMultiplayerPickableObject.set_collision_layer_value(3, true)
	$MultiplayerPickable.set_collision_layer_value(3, true)
	$ScalableMultiplayerPickableObject.original_collision_layer = $ScalableMultiplayerPickableObject.collision_layer
	$MultiplayerPickable.original_collision_layer = $MultiplayerPickable.collision_layer
	
func _on_file_dialog_file_selected(path: String):
	ui_instance.get_node("%FileDialogLayer").hide()
	ui_instance.get_node("%LoadingLayer").show()
	data_file = path

func update_shader(value:Variant, var_name:String):
	volume_layered[var_name] = value
	print('set var:', var_name, value)
	
func update_shader_colormap(name, colormap):
	volume_layered['gradient'] = colormap
	print('set gradient to ', name)


@export_file("*.zip", "*.bin") var data_file: String:
	set(value):
		if value:
			var volume_texture: ImageTexture3D = make_texture(value)
			update_texture.rpc(volume_texture)


@rpc("any_peer", "call_local", "reliable")
func update_texture(volume_texture:ImageTexture3D) -> void:
	$ScalableMultiplayerPickableObject/VolumeLayeredShader.texture = volume_texture
	ui_instance.get_node("%LoadingLayer").hide()
	ui_instance.get_node("%SettingsLayer").show()
	enable_pickables()


func texture_from_bin(data_file: String) -> ImageTexture3D:
	var shape: Vector3i = Vector3i(256, 256, 10)

	# Open the binary file
	var file: FileAccess      = FileAccess.open(data_file, FileAccess.READ)
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	var images: Array   = Array()
	var frame_size: int = shape[0] * shape[1]
	for z in range(shape[2]):
		var image = Image.new()
		var start = z * frame_size
		image.set_data(shape[0], shape[1], false, Image.FORMAT_L8, data.slice(start, start+frame_size))
		images.append(image)

	# Create a 3D texture
	var bin_texture = ImageTexture3D.new()
	bin_texture.create(Image.FORMAT_L8, shape[0], shape[1], shape[2], false, images)
	#bin_texture.init_ref()
	return bin_texture


func texture_from_zip(data_file) -> ZippedImageArchiveRFTexture3D:
	var texture: ZippedImageArchiveRFTexture3D = ZippedImageArchiveRFTexture3D.new()
	var archive                                = ZippedImageArchive_RF_3D.new()
	archive.zip_file = data_file
	texture.archive = archive
	print_debug('archive:', archive)
	return texture


func make_texture(data_file: String) -> Resource:
	if data_file.ends_with('.bin'):
		return texture_from_bin(data_file)
	elif data_file.ends_with('.zip'):
		return texture_from_zip(data_file)
	return null

	#func _enter_tree() -> void:
	#if data_file:
	#var volume_texture: ImageTexture3D = make_texture(data_file)
	#$XRToolsPickable2/VolumeLayeredShader.texture = volume_texture

func _on_multiplayer_pickable_picked_up(pickable: Variant) -> void:
	$MultiplayerPickable/aura.visible=true


func _on_multiplayer_pickable_dropped(pickable: Variant) -> void:
	$MultiplayerPickable/aura.visible=false


func _on_multiplayer_pickable_highlight_updated(pickable: Variant, enable: Variant) -> void:
	if not $MultiplayerPickable.is_picked_up():
		$MultiplayerPickable/aura.visible=true
