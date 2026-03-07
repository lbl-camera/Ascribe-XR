extends Control

# enum could like a checkbox [Smooth, faceted]
# custom types depends (Range would be something like a slider (radius))
# 
# potential layouts
# grid containers, VBOXContainer
var in_range: bool = false
@onready var container = $MarginContainer/VBoxContainer


@export var offset: float = 50.0

func setup_drop_down(enum_possibilities: Array) -> OptionButton:
	var drop_down: OptionButton = OptionButton.new()
	for possibility in enum_possibilities:
		drop_down.add_item(possibility)
	return drop_down
		

func set_property_types(type, default):
	# print(type)
	
	match type:
		"boolean":
			var check_box = CheckBox.new()
			container.add_child(check_box)
			# check_box.toggle_mode = true if default == 'true' else false
		"number":
			# if we're in a slider part don't bother
			if in_range:
				in_range = false
			
			

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
	range_container.add_theme_constant_override("separation", 750)
	slider.value = initial_position
	# range_container.theme
	
	

func make_ui(properties: Dictionary):
	# from here we can loop the attribute of each property, 
	# we should get enum, type, or something to indicate range, 
	# and then we can match off that
	print(properties['default'])
	var slider_values = []
	for type in properties.keys():
		# print(type)
		match type:
			"enum":
				var drop_down_menu = setup_drop_down(properties[type])
				drop_down_menu.selected = properties[type].find(properties['default'])
				container.add_child(drop_down_menu)
			"type":
				set_property_types(properties[type], properties['default'])
			"minimum":
				slider_values.append(properties[type])
				in_range = true
			"maximum":
				slider_values.append(properties[type])
				create_slider(slider_values, properties['default'])
		
				
				
		

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var schema = {'$schema': 'https://json-schema.org/draft/2020-12/schema', '$id': 'https://example.com/person.schema.json', 'title': 'ui_test_function', 'type': 'object', 'properties': {'radius': {'type': 'number', 'minimum': 1, 'maximum': 10, 'default': 'true'}, 'segments': {'type': 'number', 'minimum': 3, 'maximum': 128, 'default': 32}, 'style': {'enum': ['smooth', 'faceted'], 'type': 'string', 'default': 'smooth'}, 'hollow': {'type': 'boolean', 'default': 'false'}}}
	
	for keyword in schema['properties'].keys():
		# print(schema['properties'][keyword])
		var properties_dict: Dictionary = schema['properties'][keyword]
		# loop through the inner dictionary
		var new_label = Label.new()
		new_label.text = keyword
		container.add_child(new_label)
		make_ui(properties_dict) 
				
				
