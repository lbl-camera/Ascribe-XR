extends Node3D

## Test scene for the VRMenu system.
##
## Press the "ui_menu" action (Y/B button on controller, or Tab on keyboard)
## to cycle through different test menus.

var _test_index: int = 0


func _ready() -> void:
	print("MenuTest: Ready. Press menu button to cycle through test menus.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_menu"):
		_spawn_next_test_menu()


func _spawn_next_test_menu() -> void:
	match _test_index % 4:
		0:
			_test_simple_panel()
		1:
			_test_button_panel()
		2:
			_test_non_grabbable()
		3:
			_test_large_form()

	_test_index += 1


## Test 1: Simple label panel
func _test_simple_panel() -> void:
	print("MenuTest: Spawning simple label panel")
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(400, 200)

	var label = Label.new()
	label.text = "Hello from VRMenu!\nThis is a simple panel.\nGrab me with grip!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 32)
	panel.add_child(label)

	MenuManager.show_menu(panel, {
		"on_close": func(): print("MenuTest: Simple panel closed"),
	})


## Test 2: Panel with interactive buttons
func _test_button_panel() -> void:
	print("MenuTest: Spawning button panel")
	var panel = Panel.new()

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	panel.add_child(margin)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "Interactive Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	for i in range(3):
		var btn = Button.new()
		btn.text = "Option %d" % (i + 1)
		btn.add_theme_font_size_override("font_size", 28)
		btn.custom_minimum_size.y = 60
		var idx = i
		btn.pressed.connect(func(): print("MenuTest: Button %d pressed!" % (idx + 1)))
		vbox.add_child(btn)

	var close_btn = Button.new()
	close_btn.text = "Close Menu"
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.custom_minimum_size.y = 60
	close_btn.pressed.connect(func(): MenuManager.close_menu())
	vbox.add_child(close_btn)

	MenuManager.show_menu(panel, {
		"screen_size": Vector2(1.5, 1.2),
		"on_close": func(): print("MenuTest: Button panel closed"),
	})


## Test 3: Non-grabbable small dialog
func _test_non_grabbable() -> void:
	print("MenuTest: Spawning non-grabbable dialog")
	var panel = Panel.new()

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	margin.add_child(vbox)

	var label = Label.new()
	label.text = "Confirm Action?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 30)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "Yes"
	yes_btn.add_theme_font_size_override("font_size", 28)
	yes_btn.custom_minimum_size = Vector2(120, 50)
	yes_btn.pressed.connect(func():
		print("MenuTest: Confirmed!")
		MenuManager.close_menu()
	)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "No"
	no_btn.add_theme_font_size_override("font_size", 28)
	no_btn.custom_minimum_size = Vector2(120, 50)
	no_btn.pressed.connect(func():
		print("MenuTest: Cancelled!")
		MenuManager.close_menu()
	)
	hbox.add_child(no_btn)

	MenuManager.show_menu(panel, {
		"screen_size": Vector2(1.2, 0.6),
		"viewport_size": Vector2(800, 400),
		"distance": 1.2,
		"grabbable": false,
		"on_close": func(): print("MenuTest: Dialog closed"),
	})


## Test 4: Larger form with text input
func _test_large_form() -> void:
	print("MenuTest: Spawning large form")
	var panel = Panel.new()

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	# Slider
	var slider_label = Label.new()
	slider_label.text = "Brightness:"
	slider_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(slider_label)

	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 50
	slider.custom_minimum_size.y = 40
	slider.value_changed.connect(func(val): print("MenuTest: Brightness = %d" % val))
	vbox.add_child(slider)

	# Check box
	var check = CheckBox.new()
	check.text = "Enable particles"
	check.add_theme_font_size_override("font_size", 24)
	check.toggled.connect(func(on): print("MenuTest: Particles = %s" % on))
	vbox.add_child(check)

	# Spin box
	var spin_label = Label.new()
	spin_label.text = "Specimen count:"
	spin_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(spin_label)

	var spin = SpinBox.new()
	spin.min_value = 1
	spin.max_value = 20
	spin.value = 5
	spin.add_theme_font_size_override("font_size", 24)
	vbox.add_child(spin)

	# Close
	var close_btn = Button.new()
	close_btn.text = "Done"
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.custom_minimum_size.y = 50
	close_btn.pressed.connect(func(): MenuManager.close_menu())
	vbox.add_child(close_btn)

	MenuManager.show_menu(panel, {
		"screen_size": Vector2(2.5, 1.8),
		"viewport_size": Vector2(1152, 820),
		"distance": 1.8,
		"on_close": func(): print("MenuTest: Form closed"),
	})
