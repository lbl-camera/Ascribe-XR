extends ItemList


var icon_size: int = 64  # Size of the square icons

func _ready():
	populate_colormap_list()

func populate_colormap_list():
	clear()
	
	# Get all available colormaps
	var colormap_names = ColormapRegistry.get_available_colormaps()
	colormap_names.sort()  # Sort alphabetically for better organization
	
	# Set icon mode and size
	icon_mode = ItemList.ICON_MODE_TOP
	fixed_icon_size = Vector2i(icon_size, icon_size)
	
	# Add each colormap to the list
	for colormap_name in colormap_names:
		var gradient_texture = create_square_gradient_icon(colormap_name)
		add_item(colormap_name, gradient_texture)
	
	print("Added %d colormaps to the list" % colormap_names.size())

func create_square_gradient_icon(colormap_name: String) -> GradientTexture2D:
	# Create a 1D gradient first
	var gradient_1d = ColormapRegistry.create_gradient_texture_1d(colormap_name, 256)
	
	# Create a 2D gradient texture for the square icon
	var gradient_2d = GradientTexture2D.new()
	gradient_2d.gradient = gradient_1d.gradient
	gradient_2d.width = icon_size
	gradient_2d.height = icon_size
	
	# Set fill mode to horizontal (left to right gradient)
	gradient_2d.fill = GradientTexture2D.FILL_LINEAR
	gradient_2d.fill_from = Vector2(0.0, 0.5)  # Start from left middle
	gradient_2d.fill_to = Vector2(1.0, 0.5)    # End at right middle
	
	return gradient_2d

# Optional: Handle item selection
func _on_item_list_item_selected(index: int):
	var colormap_name = get_item_text(index)
	var colormap = ColormapRegistry.create_gradient_texture_1d(colormap_name)
	print("Selected colormap: ", colormap_name, colormap)
	# You can emit a signal or call a function here to handle the selection
	colormap_selected.emit(colormap_name, colormap)

# Signal for when a colormap is selected
signal colormap_selected(colormap_name: String, colormap:GradientTexture1D)

# Optional: Create a search/filter function
func filter_colormaps(search_text: String):
	clear()
	
	var colormap_names = ColormapRegistry.get_available_colormaps()
	colormap_names.sort()
	
	for colormap_name in colormap_names:
		if search_text.is_empty() or colormap_name.to_lower().contains(search_text.to_lower()):
			var gradient_texture = create_square_gradient_icon(colormap_name)
			add_item(colormap_name, gradient_texture)

# Optional: Refresh the list (useful if colormaps are added dynamically)
func refresh_colormap_list():
	populate_colormap_list()

# Optional: Get the currently selected colormap name
func get_selected_colormap() -> String:
	var selected_items = get_selected_items()
	if selected_items.size() > 0:
		return get_item_text(selected_items[0])
	return ""
