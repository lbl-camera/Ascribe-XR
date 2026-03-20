## Volumetric specimen — loads volume data and provides shader controls.
@tool
extends Specimen
class_name VolumeSpecimen

var volume_layered: VolumeLayers
var mat: ShaderMaterial


func _ready():
	volume_layered = get_node("%VolumeLayeredShader")
	var mesh_inst = volume_layered.get_child(0, true)
	mat = mesh_inst.get_surface_override_material(0)

	if ui_instance:
		for slider_name in ['gamma', 'opacity', 'color_scalar', 'max_steps', 'step_size', 'zoom']:
			var slider = ui_instance.get_node("%" + slider_name + "Slider")
			slider.value_changed.connect(_update_shader.bind(slider_name))
			slider.value = volume_layered[slider_name]
		ui_instance.get_node("%GradientItemList").colormap_selected.connect(_update_shader_colormap)
		ui_instance.get_node("%FileDialog").file_selected.connect(_on_file_dialog_file_selected)

		if volume_layered.texture:
			ui_instance.get_node("%FileDialogLayer").hide()
			ui_instance.get_node("%SettingsLayer").show()
			_enable_pickables()


func _enable_pickables() -> void:
	$ScalableMultiplayerPickableObject.show()
	$MultiplayerPickable.show()
	$ScalableMultiplayerPickableObject.set_collision_layer_value(3, true)
	$MultiplayerPickable.set_collision_layer_value(3, true)
	$ScalableMultiplayerPickableObject.original_collision_layer = $ScalableMultiplayerPickableObject.collision_layer
	$MultiplayerPickable.original_collision_layer = $MultiplayerPickable.collision_layer


func _on_file_dialog_file_selected(path: String) -> void:
	if ui_instance:
		ui_instance.get_node("%FileDialogLayer").hide()
		ui_instance.get_node("%LoadingLayer").show()
	_load_volume_file(path)


## Load a volume file using the pipeline.
func _load_volume_file(path: String) -> void:
	var p = Pipeline.file_to_volume(path)
	p.pipeline_complete.connect(_on_volume_loaded)
	p.pipeline_error.connect(func(e): push_error("VolumeSpecimen: " + e))
	p.run_pipeline()


func _on_volume_loaded(data: Data) -> void:
	if data is VolumetricData:
		var texture = data.get_data()
		if texture:
			_update_texture.rpc(texture)


@rpc("any_peer", "call_local", "reliable")
func _update_texture(volume_texture: Texture3D) -> void:
	$ScalableMultiplayerPickableObject/VolumeLayeredShader.texture = volume_texture
	if ui_instance:
		ui_instance.get_node("%LoadingLayer").hide()
		ui_instance.get_node("%SettingsLayer").show()
	_enable_pickables()


func _update_shader(value: Variant, var_name: String) -> void:
	volume_layered[var_name] = value


func _update_shader_colormap(colormap_name: String, colormap: Variant) -> void:
	volume_layered['gradient'] = colormap


# --- Legacy support for @export data_file ---

@export_file("*.zip", "*.bin") var data_file: String:
	set(value):
		if value:
			_load_volume_file(value)


func _on_multiplayer_pickable_picked_up(_pickable: Variant) -> void:
	$MultiplayerPickable/aura.visible = true


func _on_multiplayer_pickable_dropped(_pickable: Variant) -> void:
	$MultiplayerPickable/aura.visible = false


func _on_multiplayer_pickable_highlight_updated(_pickable: Variant, enable: Variant) -> void:
	if not $MultiplayerPickable.is_picked_up():
		$MultiplayerPickable/aura.visible = enable
