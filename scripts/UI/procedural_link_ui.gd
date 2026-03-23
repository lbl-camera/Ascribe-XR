extends Panel

signal ui_accept  # Legacy signal, kept for compatibility
signal loading_started
signal loading_finished
signal specimen_loaded(instance: Node)

@onready var submit_button: Button = $VBoxContainer/ButtonContainer/SubmitButton
@onready var container = $VBoxContainer/MarginContainer/VBoxContainer

var _schema: Dictionary = {}
var _schema_pending: bool = false

# Processing configuration — set these before adding to tree
var function_name: String = ""
var metadata: Dictionary = {}
var server_url: String = "http://localhost:8000"

# Internal state
var _link_client: AscribeLinkClient
var _is_processing: bool = false

@export var schema: Dictionary: 
	set(value):
		_schema = value
		if is_node_ready():
			_build_ui_from_schema()
		else:
			_schema_pending = true
	get:
		return _schema

var in_range: bool = false
var in_drop_down: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	submit_button.pressed.connect(on_submit_pressed)
	if _schema_pending:
		_build_ui_from_schema()
		_schema_pending = false
	
	# Initialize HTTP client
	_link_client = AscribeLinkClient.new(server_url)
	_link_client.setup(self)


func _build_ui_from_schema() -> void:
	if _schema.is_empty() or not _schema.has('properties'):
		return
	for keyword in _schema['properties'].keys():
		var properties_dict: Dictionary = _schema['properties'][keyword]
		var new_label = Label.new()
		new_label.text = keyword
		container.add_child(new_label)
		make_ui(properties_dict)
	#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	#schema = {'$schema': 'https://json-schema.org/draft/2020-12/schema', '$id': 'https://example.com/person.schema.json', 'title': 'ui_test_function', 'type': 'object', 'properties': {'radius': {'type': 'number', 'minimum': 1, 'maximum': 10, 'default': 1.0}, 'segments': {'type': 'number', 'minimum': 3, 'maximum': 128, 'default': 32}, 'style': {'enum': ['smooth', 'faceted'], 'type': 'string', 'default': 'smooth'}, 'hollow': {'type': 'boolean', 'default': 'false'}, 'name': {'type': 'string', 'default': 'brain'}, 'quantity': {'type': 'number', 'default': 0}}}




func setup_drop_down(enum_possibilities: Array) -> OptionButton:
	var drop_down: OptionButton = OptionButton.new()
	in_drop_down = true
	for possibility in enum_possibilities:
		drop_down.add_item(possibility)
	return drop_down
		

func set_property_types(type, default):
	# print(type)
	match type:
		"boolean":
			var check_box = CheckBox.new()
			container.add_child(check_box)
			# print(default)
			# if we want it true to start, godot's checkbox has it as false unless specified
			if default == "true":
				check_box.button_pressed = true
		"number":
			# if we're in a slider part don't bother
			if in_range:
				in_range = false
				return
			var spinBox = SpinBox.new()
			container.add_child(spinBox)
			spinBox.value = default
		"string":
			if !in_drop_down:
				var line_edit: LineEdit = LineEdit.new()
				container.add_child(line_edit)
				line_edit.text = default
			else:
				in_drop_down = false
			
			
			
			

func create_slider(slider_values: Array, initial_position):
	if initial_position is String:
		if initial_position == 'true':
			initial_position = 1.0
		elif initial_position == 'false':
			initial_position = 0.0
		else:
			return
	print(initial_position)
	var slider = HSlider.new()
	slider.ticks_on_borders = true
	var range_container = HBoxContainer.new()
	slider.min_value = slider_values[0]
	var min_label = Label.new()
	min_label.text = str(slider.min_value)
	slider.max_value = slider_values[1]
	var max_label = Label.new()
	max_label.text = str(slider.max_value)
	container.add_child(slider)
	container.add_child(range_container)
	range_container.add_child(min_label)
	range_container.add_child(max_label)
	range_container.add_theme_constant_override("separation", 1080)
	slider.value = initial_position
	# range_container.theme
	
	

func make_ui(properties: Dictionary):
	# from here we can loop the attribute of each property, 
	# we should get enum, type, or something to indicate range, 
	# and then we can match off that
	# print(properties['default'])
	var slider_values = []
	for i in range(properties.keys().size()):
		var property_type = properties.keys()[i]
		match property_type:
			"enum":
				var drop_down_menu = setup_drop_down(properties[property_type])
				drop_down_menu.selected = properties[property_type].find(properties['default'])
				container.add_child(drop_down_menu)
			"type":
				if i + 1 < properties.keys().size():
					if properties.keys()[i + 1] == "minimum":
						in_range = true
				set_property_types(properties[property_type], properties['default'])
			"minimum":
				slider_values.append(properties[property_type])
			"maximum":
				slider_values.append(properties[property_type])
				create_slider(slider_values, properties['default'])

func extract_parameters() -> Dictionary:
	var param_dict: Dictionary = {}
	var current_param_name = ""
	for ui_component in container.get_children():
		if ui_component is Label:
			current_param_name = ui_component.text
		elif ui_component is Slider:
			param_dict[current_param_name] = ui_component.value
		elif ui_component is CheckBox:
			if ui_component.button_pressed:
				param_dict[current_param_name] = true
			else:
				param_dict[current_param_name] = false
		elif ui_component is OptionButton:
			param_dict[current_param_name] = ui_component.get_item_text(ui_component.selected)
		elif ui_component is LineEdit:
			param_dict[current_param_name] = ui_component.text
		elif ui_component is SpinBox:
			param_dict[current_param_name] = ui_component.value
	return param_dict

func on_submit_pressed():
	if _is_processing:
		return
	
	var params = extract_parameters()
	print("ProceduralLinkUI: Submitting params: ", params)
	
	# Emit legacy signal for compatibility
	ui_accept.emit(params)
	
	# If function_name is set, handle the full flow ourselves
	if not function_name.is_empty():
		_process_and_load(params)


func _process_and_load(params: Dictionary) -> void:
	_is_processing = true
	loading_started.emit()
	
	# Hide form, show loading indicator
	$VBoxContainer.hide()
	
	# Get room_id from config
	var room_id = "ascribe"
	if Config.webrtcroomname:
		room_id = Config.webrtcroomname
	
	# Invoke the processing function
	var result = await _link_client.invoke_processing_function(function_name, params, room_id)
	
	if result.has("error"):
		push_error("ProceduralLinkUI: Processing failed: %s" % result.error)
		_is_processing = false
		loading_finished.emit()
		# Show form again on error
		$VBoxContainer.show()
		return
	
	# Create specimen from result
	var instance = _create_specimen_from_result(result)
	if instance:
		specimen_loaded.emit(instance)
		SceneManager.change_3d_scene_instance(instance)
	
	_is_processing = false
	loading_finished.emit()
	
	# Clean up this UI
	queue_free()


func _create_specimen_from_result(result: Dictionary) -> Node:
	var result_type = result.get("type", "")
	
	match result_type:
		"mesh":
			return _create_mesh_specimen(result)
		"volume":
			return _create_volume_specimen(result)
		_:
			push_error("ProceduralLinkUI: Unknown result type: %s" % result_type)
			return null


func _create_mesh_specimen(result: Dictionary) -> Node:
	# Create MeshData from result
	var mesh_data = MeshData.new()
	mesh_data.set_from_dict(result)
	
	# Load mesh specimen scene
	var scene = load("res://specimens/mesh_specimen.tscn")
	if not scene:
		push_error("ProceduralLinkUI: Failed to load mesh_specimen.tscn")
		return null
	
	var instance = scene.instantiate()
	
	# Set the mesh data
	if instance.has_method("set_mesh_data"):
		instance.set_mesh_data(mesh_data)
	else:
		push_error("ProceduralLinkUI: Mesh specimen doesn't have set_mesh_data method")
		instance.queue_free()
		return null
	
	# Set display name
	if "display_name" in instance:
		instance.display_name = metadata.get("display_name", "Generated Mesh")
	
	return instance


func _create_volume_specimen(result: Dictionary) -> Node:
	# Create VolumetricData from result
	var volume_data = VolumetricData.new()
	volume_data.set_from_dict(result)
	
	if not volume_data.is_valid():
		push_error("ProceduralLinkUI: Invalid volume data")
		return null
	
	# Load volume specimen scene
	var scene = load("res://specimens/volume_specimen.tscn")
	if not scene:
		push_error("ProceduralLinkUI: Failed to load volume_specimen.tscn")
		return null
	
	var instance = scene.instantiate()
	
	# Set display name
	if "display_name" in instance:
		instance.display_name = metadata.get("display_name", "Generated Volume")
	
	# Note: Volume texture needs to be applied after instance enters tree
	# The caller should handle this via the specimen_loaded signal
	instance.set_meta("_volume_data", volume_data)
	
	return instance
	
