extends ItemList

signal item_clicked_not_dragged(index)

var is_dragging: bool = false
var drag_start_pos: Vector2
var scroll_start_pos: float = 0
var pending_click_index: int = -1
var click_timer: float 
var click_delay: float = .1
var drag_threshold: int = 20

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	item_selected.connect(_on_item_selected)
	
func _on_item_selected(index:int):
	pending_click_index = index

# VR Scrolling functionality
func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start potential drag or click
				is_dragging = false
				drag_start_pos = mouse_event.position
				scroll_start_pos = get_v_scroll_bar().value
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
			var scroll_bar = get_v_scroll_bar()
			new_scroll = clamp(new_scroll, 0, scroll_bar.max_value)
			scroll_bar.value = new_scroll
			
func _handle_item_selection(index: int):
	"""Handle clicking on an item (folder navigation or file selection)"""
	if index < 0 or index >= get_item_count():
		return
		
	item_clicked_not_dragged.emit(index)
