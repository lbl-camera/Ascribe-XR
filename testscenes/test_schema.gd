extends Control

# enum could like a checkbox [Smooth, faceted]
# custom types depends (Range would be something like a slider (radius))
# 
# potential layouts
# grid containers, VBOXContainer, 

func setup_drop_down(enum_possibilities: Array):
	pass


# Called when the node enters the scene tree for the first time.
func make_ui(properties: Dictionary):
	# from here we can loop the types, we should get enum or type, and then we can match off that
	for type in properties.keys():
		print(type)
		if type == "enum":
			pass
		elif type == "type":
			match properties[type]:
				"number":
					pass
				"boolean":
					var check_box = CheckBox.new()
					add_child(check_box)

func _ready() -> void:
	var schema = {'$schema': 'https://json-schema.org/draft/2020-12/schema', '$id': 'https://example.com/person.schema.json', 'title': 'ui_test_function', 'type': 'object', 'properties': {'radius': {'type': 'number'}, 'segments': {'type': 'number'}, 'style': {'enum': ['smooth', 'faceted'], 'type': 'string'}, 'hollow': {'type': 'boolean'}}}
	
	for keyword in schema['properties'].keys():
		print(schema['properties'][keyword])
		var properties_dict: Dictionary = schema['properties'][keyword]
		# loop through the inner dictionary
		make_ui(properties_dict) 
				
				
