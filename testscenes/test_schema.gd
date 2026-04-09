extends Control

# enum could like a checkbox [Smooth, faceted]
# custom types depends (Range would be something like a slider (radius))
#
# potential layouts
# grid containers, VBOXContainer

@onready var container = $ProceduralLinkUI

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var schema = {'$schema': 'https://json-schema.org/draft/2020-12/schema', '$id': 'https://example.com/person.schema.json', 'title': 'ui_test_function', 'type': 'object', 'properties': {'radius': {'type': 'number', 'minimum': 1, 'maximum': 10, 'default': 1.0}, 'segments': {'type': 'number', 'minimum': 3, 'maximum': 128, 'default': 32}, 'style': {'enum': ['smooth', 'faceted'], 'type': 'string', 'default': 'smooth'}, 'hollow': {'type': 'boolean', 'default': 'false'}, 'name': {'type': 'string', 'default': 'brain'}, 'quantity': {'type': 'number', 'default': 0}}}

	container.schema = schema
