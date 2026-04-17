extends Panel

## Builds a form from a JSON Schema and defers submission to SceneManager.
## Submission, progress, and result loading are coordinated across peers by
## SceneManager RPCs, so each connected client runs the same state machine.

signal ui_accept  # Legacy signal, kept for compatibility
signal loading_started
signal loading_finished
signal specimen_loaded(instance: Node)


@onready var submit_button: Button = %SubmitButton
@onready var proc_ui_container = %ProceduralForm

var _schema: Dictionary = {}
var _schema_pending: bool = false

# Processing configuration — set these before adding to tree
var function_name: String = ""
var metadata: Dictionary = {}
var server_url: String = "http://localhost:8000"

# Internal state
var _progress_label: RichTextLabel = null
var _last_params: Dictionary = {}
var _submitted: bool = false

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
var _is_applying_remote_value: bool = false
var slider_dict: Dictionary = {}
var slider_spin_box: SpinBox = null
var slider_h_box: HBoxContainer = null
var param_controls: Dictionary = {}
var current_container: Container


func _ready() -> void:
	submit_button.pressed.connect(on_submit_pressed)
	if _schema_pending:
		_build_ui_from_schema.rpc()
		_schema_pending = false

@rpc("any_peer", "call_local", "reliable")
func _build_ui_from_schema() -> void:
	if _schema.is_empty() or not _schema.has("properties"):
		return
	# clearing out everything between peers
	for child in proc_ui_container.get_children():
		child.queue_free()

	param_controls.clear()
	slider_dict.clear()
	in_range = false
	in_drop_down = false
	param_controls.clear()

	for keyword in _schema["properties"].keys():
		
		var properties_dict: Dictionary = _schema["properties"][keyword]
		var new_label = Label.new()
		current_container = HBoxContainer.new()
		current_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		current_container.add_theme_constant_override("separation", 12)
		current_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		new_label.text = keyword
		new_label.text = new_label.text.capitalize()
		new_label.custom_minimum_size.x = 120
		new_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		new_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		current_container.add_child(new_label)
		make_ui(properties_dict, keyword)
		proc_ui_container.add_child(current_container)
		var separator: HSeparator = HSeparator.new()
		separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		proc_ui_container.add_child(separator)


func setup_drop_down(enum_possibilities: Array) -> OptionButton:
	var drop_down: OptionButton = OptionButton.new()
	drop_down.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	in_drop_down = true
	for possibility in enum_possibilities:
		drop_down.add_item(possibility)
	return drop_down


func set_property_types(type, default, param_name: String):
	match type:
		"boolean":
			var check_box := CheckBox.new()
			current_container.add_child(check_box)
			check_box.button_pressed = (default == true or default == "true")
			check_box.toggled.connect(func(pressed: bool):
				_send_param_value(param_name, pressed)
			)
			param_controls[param_name] = check_box

		"number":
			if in_range:
				in_range = false
				return

			var spin_box := SpinBox.new()
			spin_box.value = default
			spin_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			current_container.add_child(spin_box)

			spin_box.value_changed.connect(func(new_value: float):
				_send_param_value(param_name, new_value)
			)

			param_controls[param_name] = spin_box

		"textarea":
			var multiline := TextEdit.new()
			multiline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			multiline.text = str(default)
			multiline.custom_minimum_size.y = 80
			setup_autogrow_text_edit(multiline, 2, 10)
			current_container.add_child(multiline)

			multiline.text_changed.connect(func():
				_send_param_value(param_name, multiline.text)
			)

			param_controls[param_name] = multiline

		"string":
			if !in_drop_down:
				var line_edit := LineEdit.new()
				line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line_edit.text = str(default)
				line_edit.focus_entered.connect(_on_text_section_entered)
				current_container.add_child(line_edit)

				line_edit.text_changed.connect(func(new_text: String):
					_send_param_value(param_name, new_text)
				)

				param_controls[param_name] = line_edit
			else:
				in_drop_down = false

@rpc("any_peer", "call_local", "reliable")
func apply_param_value(param_name: String, value) -> void:
	if not param_controls.has(param_name):
		return
	print("RECEIVED ", multiplayer.get_unique_id(), " ", param_name, " = ", value)
	_is_applying_remote_value = true

	var control = param_controls[param_name]

	if control is HSlider:
		control.value = float(value)
	elif control is SpinBox:
		control.value = float(value)
	elif control is CheckBox:
		control.button_pressed = bool(value)
	elif control is OptionButton:
		control.select(int(value))
	elif control is LineEdit:
		control.text = str(value)
	elif control is TextEdit:
		control.text = str(value)

	_is_applying_remote_value = false

func _send_param_value(param_name: String, value) -> void:
	if _is_applying_remote_value:
		return
	print("proc ui path: ", get_path())
	print("multiplayer authority: ", get_multiplayer_authority())
	print("unique id: ", multiplayer.get_unique_id())
	print("SENDING ", multiplayer.get_unique_id(), " ", param_name, " = ", value)
	apply_param_value.rpc(param_name, value)


func create_slider(slider_values: Array, initial_position, param_name: String):
	var slider_row := HBoxContainer.new()
	var slider_container := VBoxContainer.new()

	slider_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.add_theme_constant_override("separation", 8)

	if initial_position is String:
		if initial_position == "true":
			initial_position = 1.0
		elif initial_position == "false":
			initial_position = 0.0
		else:
			return

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.ticks_on_borders = true
	slider.min_value = slider_values[0]
	slider.max_value = slider_values[1]
	slider.value = initial_position

	var spin_box := SpinBox.new()
	spin_box.min_value = slider_values[0]
	spin_box.max_value = slider_values[1]
	spin_box.value = initial_position
	spin_box.custom_minimum_size.x = 80

	slider_row.add_child(slider)
	slider_row.add_child(spin_box)

	var range_row := HBoxContainer.new()
	range_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_row.add_theme_constant_override("separation", 8)

	var slider_range := HBoxContainer.new()
	slider_range.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var min_label := Label.new()
	min_label.text = str(slider.min_value)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var max_label := Label.new()
	max_label.text = str(slider.max_value)
	max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	slider_range.add_child(min_label)
	slider_range.add_child(spacer)
	slider_range.add_child(max_label)

	var spinbox_spacer := Control.new()
	spinbox_spacer.custom_minimum_size.x = spin_box.custom_minimum_size.x

	range_row.add_child(slider_range)
	range_row.add_child(spinbox_spacer)

	slider_container.add_child(slider_row)
	slider_container.add_child(range_row)

	slider_dict[slider] = spin_box
	param_controls[param_name] = slider

	slider.value_changed.connect(func(new_value: float):
		if _is_applying_remote_value:
			return
		if slider_dict.has(slider):
			slider_dict[slider].value = new_value
		_send_param_value(param_name, new_value)
	)

	spin_box.value_changed.connect(func(new_value: float):
		if _is_applying_remote_value:
			return
		slider.value = new_value
		_send_param_value(param_name, new_value)
	)

	current_container.add_child(slider_container)

func setup_autogrow_text_edit(text_edit: TextEdit, min_lines: int = 2, max_lines: int = 8) -> void:
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.scroll_fit_content_height = true
	text_edit.text_changed.connect(_on_text_edit_text_changed.bind(text_edit, min_lines, max_lines))

	_update_text_edit_height(text_edit, min_lines, max_lines)
	
func _on_text_edit_text_changed(text_edit: TextEdit, min_lines: int, max_lines: int) -> void:
	_update_text_edit_height(text_edit, min_lines, max_lines)

func _update_text_edit_height(text_edit: TextEdit, min_lines: int, max_lines: int) -> void:
	var line_count := text_edit.get_total_visible_line_count()
	line_count = clamp(line_count, min_lines, max_lines)

	var line_height := text_edit.get_line_height()
	var top_padding := 8
	var bottom_padding := 8

	text_edit.custom_minimum_size.y = line_count * line_height + top_padding + bottom_padding
	
func _get_default_for_type(properties: Dictionary) -> Variant:
	if properties.has('default'):
		return properties['default']

	var prop_type = properties.get('type', '')
	match prop_type:
		"textarea":
			return ""
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

	if properties.has("enum"):
		var drop_down_menu = setup_drop_down(properties["enum"])
		drop_down_menu.selected = properties["enum"].find(default_value)
		current_container.add_child(drop_down_menu)
		drop_down_menu.item_selected.connect(func(index: int):
			_send_param_value(param_name, index)
		)
		param_controls[param_name] = drop_down_menu
		return

	if properties.get("type") == "number" and properties.has("minimum") and properties.has("maximum"):
		create_slider([properties["minimum"], properties["maximum"]], default_value, param_name)
		return

	if properties.has("type"):
		set_property_types(properties["type"], default_value, param_name)

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
		elif control is LineEdit or control is TextEdit:
			param_dict[param_name] = control.text

	return param_dict


func on_slider_value_changed(new_value: float, slider: HSlider) -> void:
	if slider_dict.has(slider):
		var spin_box: SpinBox = slider_dict[slider]
		spin_box.value = new_value


func on_spinbox_value_changed(new_value: float, slider: HSlider) -> void:
	if slider_dict.has(slider):
		slider.value = new_value


func _on_text_section_entered():
	print("keyboard")
	DisplayServer.virtual_keyboard_show("")

# ---------------------------------------------------------------------------
# Multiplayer submission — SceneManager coordinates the rest.
# ---------------------------------------------------------------------------

func on_submit_pressed() -> void:
	if _submitted:
		return
	if function_name.is_empty():
		push_error("ProceduralLinkUI: function_name not set")
		return

	_submitted = true
	_last_params = extract_parameters()
	ui_accept.emit(_last_params)
	SceneManager.request_submit(function_name, _last_params)


## Called via SceneManager RPC once any peer has submitted: hide the form,
## show a progress panel so every client sees the same loading screen.
func enter_loading_state() -> void:
	proc_ui_container.hide()
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
	_progress_label.custom_minimum_size = Vector2(0, 400)

	var vbox = get_node_or_null("MarginContainer/VBoxContainer2")
	if vbox:
		# Keep ButtonContainer last so it stays visible at the bottom.
		vbox.add_child(_progress_label)
		var button_container := vbox.get_node_or_null("ButtonContainer")
		if button_container:
			vbox.move_child(button_container, vbox.get_child_count() - 1)
	else:
		add_child(_progress_label)
