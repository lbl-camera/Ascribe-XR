extends Panel

## Builds a form from a JSON Schema and defers submission to SceneManager.
## Submission, progress, and result loading are coordinated across peers by
## SceneManager RPCs, so each connected client runs the same state machine.

signal ui_accept  # Legacy signal, kept for compatibility
signal slider_changed(slider)

@onready var submit_button: Button = %SubmitButton
@onready var container = %ProceduralForm

var _schema: Dictionary = {}
var _schema_pending: bool = false

# Processing configuration — set these before adding to tree
var function_name: String = ""
var metadata: Dictionary = {}
var server_url: String = "http://localhost:8000"

# Internal state
var _progress_label: RichTextLabel = null
var _last_params: Dictionary = {}

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
var slider_dict: Dictionary = {}
var slider_spin_box: SpinBox = null
var slider_h_box: HBoxContainer = null
var param_controls: Dictionary = {}


func _ready() -> void:
	submit_button.pressed.connect(on_submit_pressed)
	if _schema_pending:
		_build_ui_from_schema()
		_schema_pending = false


func _build_ui_from_schema() -> void:
	if _schema.is_empty() or not _schema.has("properties"):
		return

	param_controls.clear()

	for keyword in _schema["properties"].keys():
		var properties_dict: Dictionary = _schema["properties"][keyword]
		var new_label = Label.new()
		new_label.text = keyword

		var prop_type = properties_dict.get("type", "")
		if prop_type == "number" and properties_dict.has("minimum"):
			slider_h_box = HBoxContainer.new()
			container.add_child(slider_h_box)
			slider_h_box.add_child(new_label)

			slider_spin_box = SpinBox.new()
			if properties_dict.has("default"):
				slider_spin_box.value = properties_dict["default"]
			slider_h_box.add_child(slider_spin_box)

			param_controls[keyword] = slider_spin_box
		else:
			container.add_child(new_label)

		make_ui(properties_dict, keyword)


func setup_drop_down(enum_possibilities: Array) -> OptionButton:
	var drop_down: OptionButton = OptionButton.new()
	in_drop_down = true
	for possibility in enum_possibilities:
		drop_down.add_item(possibility)
	return drop_down


func set_property_types(type, default, param_name: String):
	match type:
		"boolean":
			var check_box = CheckBox.new()
			container.add_child(check_box)
			if default == "true":
				check_box.button_pressed = true
			param_controls[param_name] = check_box

		"number":
			if in_range:
				in_range = false
				return
			var spin_box = SpinBox.new()
			container.add_child(spin_box)
			spin_box.value = default
			param_controls[param_name] = spin_box

		"string":
			if !in_drop_down:
				var line_edit: LineEdit = LineEdit.new()
				container.add_child(line_edit)
				line_edit.text = default
				param_controls[param_name] = line_edit
			else:
				in_drop_down = false


func create_slider(slider_values: Array, initial_position, param_name: String):
	if initial_position is String:
		if initial_position == "true":
			initial_position = 1.0
		elif initial_position == "false":
			initial_position = 0.0
		else:
			return

	var slider = HSlider.new()
	slider.ticks_on_borders = true

	var range_container = HBoxContainer.new()

	slider.min_value = slider_values[0]
	slider_spin_box.min_value = slider_values[0]

	var min_label = Label.new()
	min_label.text = str(slider.min_value)

	slider.max_value = slider_values[1]
	slider_spin_box.max_value = slider_values[1]

	var max_label = Label.new()
	max_label.text = str(slider.max_value)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	container.add_child(slider)
	container.add_child(range_container)

	range_container.add_child(min_label)
	range_container.add_child(spacer)
	range_container.add_child(max_label)

	slider.value = initial_position
	slider_spin_box.value = initial_position

	slider_dict[slider] = slider_spin_box
	param_controls[param_name] = slider

	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_slider_value_changed.bind(slider))
	slider_spin_box.value_changed.connect(on_spinbox_value_changed.bind(slider))


func _get_default_for_type(properties: Dictionary) -> Variant:
	if properties.has('default'):
		return properties['default']

	var prop_type = properties.get('type', '')
	match prop_type:
		"string":
			return ""
		"number":
			return properties.get('minimum', 0.0)
		"boolean":
			return false

	if properties.has('enum') and properties['enum'].size() > 0:
		return properties['enum'][0]

	return ""


func make_ui(properties: Dictionary, param_name: String):
	var default_value = _get_default_for_type(properties)
	var slider_values = []
	for i in range(properties.keys().size()):
		var property_type = properties.keys()[i]
		match property_type:
			"enum":
				var drop_down_menu = setup_drop_down(properties[property_type])
				drop_down_menu.selected = properties[property_type].find(default_value)
				container.add_child(drop_down_menu)
				param_controls[param_name] = drop_down_menu

			"type":
				if i + 1 < properties.keys().size():
					if properties.keys()[i + 1] == "minimum":
						in_range = true
				set_property_types(properties[property_type], default_value, param_name)
			"minimum":
				slider_values.append(properties[property_type])

			"maximum":
				slider_values.append(properties[property_type])
	if slider_values:
		create_slider(slider_values, default_value, param_name)


func extract_parameters() -> Dictionary:
	var param_dict: Dictionary = {}

	for param_name in param_controls.keys():
		var control = param_controls[param_name]

		if control is HSlider:
			param_dict[param_name] = control.value
		elif control is SpinBox:
			param_dict[param_name] = control.value
		elif control is CheckBox:
			param_dict[param_name] = control.button_pressed
		elif control is OptionButton:
			param_dict[param_name] = control.get_item_text(control.selected)
		elif control is LineEdit:
			param_dict[param_name] = control.text

	return param_dict


func on_slider_value_changed(new_value: float, slider: HSlider) -> void:
	if slider_dict.has(slider):
		var spin_box: SpinBox = slider_dict[slider]
		spin_box.value = new_value


func on_spinbox_value_changed(new_value: float, slider: HSlider) -> void:
	if slider_dict.has(slider):
		slider.value = new_value


# ---------------------------------------------------------------------------
# Multiplayer submission — SceneManager coordinates the rest.
# ---------------------------------------------------------------------------

func on_submit_pressed() -> void:
	if function_name.is_empty():
		push_error("ProceduralLinkUI: function_name not set")
		return

	_last_params = extract_parameters()
	ui_accept.emit(_last_params)
	SceneManager.request_submit(function_name, _last_params)


## Called via SceneManager RPC once any peer has submitted: hide the form,
## show a progress panel so every client sees the same loading screen.
func enter_loading_state() -> void:
	container.hide()
	submit_button.hide()
	_show_progress_ui()


func append_progress(text: String) -> void:
	if _progress_label == null:
		_show_progress_ui()
	_progress_label.append_text(text + "\n")


func show_error(error: String) -> void:
	if _progress_label == null:
		_show_progress_ui()
	_progress_label.append_text("\n[ERROR] " + error + "\n")


func get_last_params() -> Dictionary:
	if _last_params.is_empty():
		_last_params = extract_parameters()
	return _last_params


func _show_progress_ui() -> void:
	if _progress_label != null:
		return
	_progress_label = RichTextLabel.new()
	_progress_label.name = "ProgressLog"
	_progress_label.bbcode_enabled = false
	_progress_label.scroll_following = true
	_progress_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox = get_node_or_null("MarginContainer/VBoxContainer2")
	if vbox:
		vbox.add_child(_progress_label)
	else:
		add_child(_progress_label)
