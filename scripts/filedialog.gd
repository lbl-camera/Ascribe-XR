@tool
extends MarginContainer
class_name XRFileDialog

## XR-Friendly File Dialog
## A simplified file dialog that uses single-clicks instead of double-clicks

signal file_selected(path: String)
signal canceled()

@onready var path_edit: LineEdit = $VBoxContainer/UpperButtonContainer/PathLineEdit
@onready var file_list: ItemList = $VBoxContainer/FileList
@onready var select_button: Button = $VBoxContainer/LowerButtonContainer/Container/SelectButton
@onready var cancel_button: Button = $VBoxContainer/LowerButtonContainer/Control/CancelButton
@onready var up_button: Button = $VBoxContainer/UpperButtonContainer/UpButton
@onready var back_button: Button = $VBoxContainer/UpperButtonContainer/BackButton
@onready var forward_button: Button = $VBoxContainer/UpperButtonContainer/ForwardButton
@onready var refresh_button: Button = $VBoxContainer/UpperButtonContainer/RefreshButton
@onready var filter: Label = $VBoxContainer/HBoxContainer/Filter
@onready var selected_file: LineEdit = $VBoxContainer/HBoxContainer/SelectedFile


@export_dir var current_path: String = ""
var file_access: DirAccess
var navigation_history = []
var history_index = 0
@export var file_filters:Array[String] = []
var is_dragging: bool = false
var drag_start_pos: Vector2
var scroll_start_pos: float = 0
var pending_click_index: int = -1
var click_timer: float 
var click_delay: float = .1
var drag_threshold: int = 10


func _ready():
	# Connect signals
	select_button.pressed.connect(_on_select_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	up_button.pressed.connect(_on_up_pressed)
	back_button.pressed.connect(_on_back_pressed)
	forward_button.pressed.connect(_on_forward_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	path_edit.text_submitted.connect(_on_path_submitted)
	selected_file.text_submitted.connect(_on_file_name_submitted)
	
	# Connect VR scrolling for file list - use gui_input instead of item_selected
	file_list.gui_input.connect(_on_file_list_gui_input)
	file_list.item_selected.connect(_on_file_list_item_selected)
	
	# Start in user directory or current directory
	current_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if current_path.is_empty():
		current_path = OS.get_executable_path().get_base_dir()
	
	# Normalize the path
	current_path = _normalize_path(current_path)
	_refresh_directory()
	
	#show the filter
	$VBoxContainer/HBoxContainer/Filter.text = ", ".join(file_filters)

func _normalize_path(path: String) -> String:
	"""Normalize path to use consistent separators and format"""
	if path.is_empty():
		return path
	
	# Convert to absolute path and simplify
	var normalized = ProjectSettings.globalize_path(path)
	if normalized.is_empty():
		normalized = path
	
	# Ensure we use the correct path separator for the platform
	normalized = normalized.replace("\\", "/")
	
	# Remove trailing separator if present (except for root)
	if normalized.length() > 1 and normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	
	return normalized

func _refresh_directory():
	if current_path.is_empty():
		return
	
	# Normalize current path
	current_path = _normalize_path(current_path)
		
	file_list.clear()
	path_edit.text = current_path
	selected_file.text = ""
	
	file_access = DirAccess.open(current_path)
	if file_access == null:
		push_error("Could not open directory: " + current_path)
		return
	
	# Add to navigation history if this is a new path
	if navigation_history.is_empty() or (history_index < 0) or navigation_history[history_index] != current_path:
		# Remove any forward history when navigating to a new path
		if history_index >= 0:
			navigation_history = navigation_history.slice(0, history_index + 1)
		navigation_history.append(current_path)
		history_index = navigation_history.size() - 1
	
	_update_navigation_buttons()
	
	file_access.list_dir_begin()
	var file_name = file_access.get_next()
	
	# Add directories first
	var directories = []
	var files = []
	
	while file_name != "":
		if file_access.current_is_dir() and not file_name.begins_with("."):
			directories.append(file_name)
		elif not file_access.current_is_dir() and _passes_filter(file_name):
			files.append(file_name)
		file_name = file_access.get_next()
	
	# Sort and add to list
	directories.sort()
	files.sort()
	
	for dir_name in directories:
		file_list.add_item("📁 " + dir_name)
		file_list.set_item_metadata(file_list.get_item_count() - 1, {"type": "directory", "name": dir_name})
	
	for file_name_item in files:
		file_list.add_item("📄 " + file_name_item)
		file_list.set_item_metadata(file_list.get_item_count() - 1, {"type": "file", "name": file_name_item})

func _process(delta):
	# Handle pending clicks after delay
	if pending_click_index >= 0:
		click_timer += delta
		if click_timer >= click_delay and not is_dragging:
			# Process the delayed click
			_handle_item_selection(pending_click_index)
			pending_click_index = -1
			click_timer = 0.0

func _on_select_pressed():
	var file_path: String
	
	if not selected_file.text.is_empty():
		# Use the typed filename
		file_path = current_path + "/" + selected_file.text
	else:
		# Use selected item from list
		var selected_items = file_list.get_selected_items()
		if selected_items.size() > 0:
			var metadata = file_list.get_item_metadata(selected_items[0])
			if metadata.type == "file":
				file_path = current_path + "/" + metadata.name
	
	if not file_path.is_empty():
		file_selected.emit(_normalize_path(file_path))

func _on_cancel_pressed():
	canceled.emit()

func _on_up_pressed():
	var parent_path = current_path.get_base_dir()
	if parent_path != current_path:  # Avoid infinite loop at root
		current_path = _normalize_path(parent_path)
		_refresh_directory()

# Navigation button handlers
func _on_back_pressed():
	if history_index > 0:
		history_index -= 1
		current_path = navigation_history[history_index]
		# Don't call _refresh_directory() directly to avoid adding to history
		_refresh_directory_no_history()

func _on_forward_pressed():
	if history_index < navigation_history.size() - 1:
		history_index += 1
		current_path = navigation_history[history_index]
		# Don't call _refresh_directory() directly to avoid adding to history
		_refresh_directory_no_history()

func _on_refresh_pressed():
	_refresh_directory()

func _on_path_submitted(new_path: String):
	var normalized_path = _normalize_path(new_path)
	if DirAccess.dir_exists_absolute(normalized_path):
		current_path = normalized_path
		_refresh_directory()
	else:
		# Revert to current path if invalid
		path_edit.text = current_path

func _on_file_name_submitted(file_name: String):
	if not file_name.is_empty():
		_on_select_pressed()

# Helper functions
func _refresh_directory_no_history():
	"""Refresh directory without modifying navigation history"""
	current_path = _normalize_path(current_path)
	
	file_list.clear()
	path_edit.text = current_path
	selected_file.text = ""
	
	file_access = DirAccess.open(current_path)
	if file_access == null:
		push_error("Could not open directory: " + current_path)
		return
	
	_update_navigation_buttons()
	
	file_access.list_dir_begin()
	var file_name = file_access.get_next()
	
	var directories = []
	var files = []
	
	while file_name != "":
		if file_access.current_is_dir() and not file_name.begins_with("."):
			directories.append(file_name)
		elif not file_access.current_is_dir() and _passes_filter(file_name):
			files.append(file_name)
		file_name = file_access.get_next()
	
	directories.sort()
	files.sort()
	
	for dir_name in directories:
		file_list.add_item("📁 " + dir_name)
		file_list.set_item_metadata(file_list.get_item_count() - 1, {"type": "directory", "name": dir_name})
	
	for file_name_item in files:
		file_list.add_item("📄 " + file_name_item)
		file_list.set_item_metadata(file_list.get_item_count() - 1, {"type": "file", "name": file_name_item})

func _update_navigation_buttons():
	back_button.disabled = history_index <= 0
	forward_button.disabled = history_index >= navigation_history.size() - 1

func _passes_filter(file_name: String) -> bool:
	"""Check if file passes the current filter"""
	if file_filters.is_empty() or file_filters[0] == "*":
		return true
	
	for filter_pattern in file_filters:
		if filter_pattern == "*":
			return true
		elif filter_pattern.begins_with("*."):
			var extension = filter_pattern.substr(2)
			if file_name.get_extension().to_lower() == extension.to_lower():
				return true
		elif file_name.match(filter_pattern):
			return true
	
	return false

func _update_filter_display():
	"""Update the filter label display"""
	if file_filters.is_empty() or file_filters[0] == "*":
		filter.text = "All Files (*)"
	else:
		filter.text = "Filter: " + ", ".join(file_filters)

func _on_file_list_item_selected(index:int):
	pending_click_index = index

# VR Scrolling functionality
func _on_file_list_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start potential drag or click
				is_dragging = false
				drag_start_pos = mouse_event.position
				scroll_start_pos = file_list.get_v_scroll_bar().value
				click_timer = 0.0
				
			else:
				# End drag or finalize click
				if is_dragging:
					is_dragging = false
					pending_click_index = -1
				elif pending_click_index >= 0:
					# If we haven't started dragging and haven't waited long enough, process click immediately
					if click_timer < click_delay:
						_handle_item_selection(pending_click_index)
					pending_click_index = -1
					click_timer = 0.0
	
	elif event is InputEventMouseMotion:
		var mouse_motion = event as InputEventMouseMotion
		
		# Check if we should start dragging
		if pending_click_index >= 0 and not is_dragging:
			var distance = mouse_motion.position.distance_to(drag_start_pos)
			if distance > drag_threshold:
				# Start dragging - cancel any pending click
				is_dragging = true
				pending_click_index = -1
				click_timer = 0.0
		
		# Handle drag scrolling
		if is_dragging:
			var delta_y = mouse_motion.position.y - drag_start_pos.y
			
			# Convert pixel movement to scroll movement
			var scroll_sensitivity = 2.0
			var new_scroll = scroll_start_pos - (delta_y * scroll_sensitivity)
			
			# Clamp to valid scroll range
			var scroll_bar = file_list.get_v_scroll_bar()
			new_scroll = clamp(new_scroll, 0, scroll_bar.max_value)
			scroll_bar.value = new_scroll

func _get_item_at_position(pos: Vector2) -> int:
	"""Get the item index at the given position, or -1 if none"""
	var item_count = file_list.get_item_count()
	for i in range(item_count):
		var item_rect = file_list.get_item_rect(i)
		if item_rect.has_point(pos):
			return i
	return -1

func _handle_item_selection(index: int):
	"""Handle clicking on an item (folder navigation or file selection)"""
	if index < 0 or index >= file_list.get_item_count():
		return
		
	var metadata = file_list.get_item_metadata(index)
	if metadata.type == "directory":
		# Navigate into directory on single click
		# Use proper path joining with normalization
		var new_path = current_path + "/" + metadata.name
		current_path = _normalize_path(new_path)
		_refresh_directory()
	else:
		# Select file and update the selected file field
		file_list.select(index)  # Visually select the item
		selected_file.text = metadata.name
		select_button.disabled = false
