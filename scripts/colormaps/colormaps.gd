# ColormapRegistry.gd
# Godot implementation of matplotlib colormap data
# Usage: var colormap = ColormapRegistry.get_colormap("viridis")

extends Resource
class_name ColormapRegistry

# Color data for continuous colormaps (LinearSegmentedColormap equivalent)
static var _continuous_colormaps = {}

# Color data for discrete colormaps (ListedColormap equivalent) 
static var _discrete_colormaps = {}

# Initialize colormap data when first accessed
static var _initialized = false

static func _init_colormaps():
	if _initialized:
		return
	_initialized = true
	
	# Binary colormap
	_continuous_colormaps["binary"] = {
		"red": [[0.0, 1.0, 1.0], [1.0, 0.0, 0.0]],
		"green": [[0.0, 1.0, 1.0], [1.0, 0.0, 0.0]],
		"blue": [[0.0, 1.0, 1.0], [1.0, 0.0, 0.0]]
	}
	
	# Autumn colormap
	_continuous_colormaps["autumn"] = {
		"red": [[0.0, 1.0, 1.0], [1.0, 1.0, 1.0]],
		"green": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"blue": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]]
	}
	
	# Hot colormap
	_continuous_colormaps["hot"] = {
		"red": [[0.0, 0.0416, 0.0416], [0.365079, 1.0, 1.0], [1.0, 1.0, 1.0]],
		"green": [[0.0, 0.0, 0.0], [0.365079, 0.0, 0.0], [0.746032, 1.0, 1.0], [1.0, 1.0, 1.0]],
		"blue": [[0.0, 0.0, 0.0], [0.746032, 0.0, 0.0], [1.0, 1.0, 1.0]]
	}
	
	# Cool colormap
	_continuous_colormaps["cool"] = {
		"red": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"green": [[0.0, 1.0, 1.0], [1.0, 0.0, 0.0]],
		"blue": [[0.0, 1.0, 1.0], [1.0, 1.0, 1.0]]
	}
	
	# Spring colormap
	_continuous_colormaps["spring"] = {
		"red": [[0.0, 1.0, 1.0], [1.0, 1.0, 1.0]],
		"green": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"blue": [[0.0, 1.0, 1.0], [1.0, 0.0, 0.0]]
	}
	
	# Summer colormap
	_continuous_colormaps["summer"] = {
		"red": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"green": [[0.0, 0.5, 0.5], [1.0, 1.0, 1.0]],
		"blue": [[0.0, 0.4, 0.4], [1.0, 0.4, 0.4]]
	}
	
	# Winter colormap
	_continuous_colormaps["winter"] = {
		"red": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]],
		"green": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"blue": [[0.0, 1.0, 1.0], [1.0, 0.5, 0.5]]
	}
	
	# Gray/Grey colormap
	_continuous_colormaps["gray"] = {
		"red": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"green": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"blue": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]]
	}
	_continuous_colormaps["grey"] = _continuous_colormaps["gray"]
	
	# Jet colormap
	_continuous_colormaps["jet"] = {
		"red": [[0.0, 0.0, 0.0], [0.35, 0.0, 0.0], [0.66, 1.0, 1.0], [0.89, 1.0, 1.0], [1.0, 0.5, 0.5]],
		"green": [[0.0, 0.0, 0.0], [0.125, 0.0, 0.0], [0.375, 1.0, 1.0], [0.64, 1.0, 1.0], [0.91, 0.0, 0.0], [1.0, 0.0, 0.0]],
		"blue": [[0.0, 0.5, 0.5], [0.11, 1.0, 1.0], [0.34, 1.0, 1.0], [0.65, 0.0, 0.0], [1.0, 0.0, 0.0]]
	}
	
	# Viridis-like colormap (simplified version)
	_continuous_colormaps["viridis"] = {
		"red": [[0.0, 0.267004, 0.267004], [0.25, 0.229739, 0.229739], [0.5, 0.127568, 0.127568], [0.75, 0.365570, 0.365570], [1.0, 0.993248, 0.993248]],
		"green": [[0.0, 0.004874, 0.004874], [0.25, 0.322361, 0.322361], [0.5, 0.566949, 0.566949], [0.75, 0.800589, 0.800589], [1.0, 0.906157, 0.906157]],
		"blue": [[0.0, 0.329415, 0.329415], [0.25, 0.545706, 0.545706], [0.5, 0.550556, 0.550556], [0.75, 0.382914, 0.382914], [1.0, 0.143936, 0.143936]]
	}
	
	# BWR (Blue-White-Red) discrete colormap
	_discrete_colormaps["bwr"] = [
		Color(0.0, 0.0, 1.0, 1.0),  # Blue
		Color(1.0, 1.0, 1.0, 1.0),  # White  
		Color(1.0, 0.0, 0.0, 1.0)   # Red
	]
	
	# Tab10 qualitative colormap
	_discrete_colormaps["tab10"] = [
		Color(0.12156862745098039, 0.4666666666666667, 0.7058823529411765, 1.0),
		Color(1.0, 0.4980392156862745, 0.054901960784313725, 1.0),
		Color(0.17254901960784313, 0.6274509803921569, 0.17254901960784313, 1.0),
		Color(0.8392156862745098, 0.15294117647058825, 0.1568627450980392, 1.0),
		Color(0.5803921568627451, 0.403921568627451, 0.7411764705882353, 1.0),
		Color(0.5490196078431373, 0.33725490196078434, 0.29411764705882354, 1.0),
		Color(0.8901960784313725, 0.4666666666666667, 0.7607843137254902, 1.0),
		Color(0.4980392156862745, 0.4980392156862745, 0.4980392156862745, 1.0),
		Color(0.7372549019607844, 0.7411764705882353, 0.13333333333333333, 1.0),
		Color(0.09019607843137255, 0.7450980392156863, 0.8117647058823529, 1.0)
	]
	
	# Set1 qualitative colormap
	_discrete_colormaps["Set1"] = [
		Color(0.89411764705882357, 0.10196078431372549, 0.10980392156862745, 1.0),
		Color(0.21568627450980393, 0.49411764705882355, 0.72156862745098038, 1.0),
		Color(0.30196078431372547, 0.68627450980392157, 0.29019607843137257, 1.0),
		Color(0.59607843137254901, 0.30588235294117649, 0.63921568627450975, 1.0),
		Color(1.0, 0.49803921568627452, 0.0, 1.0),
		Color(1.0, 1.0, 0.2, 1.0),
		Color(0.65098039215686276, 0.33725490196078434, 0.15686274509803921, 1.0),
		Color(0.96862745098039216, 0.50588235294117645, 0.74901960784313726, 1.0),
		Color(0.6, 0.6, 0.6, 1.0)
	]

# Get a colormap by name
static func get_colormap(name: String) -> Dictionary:
	_init_colormaps()
	
	if _continuous_colormaps.has(name):
		return {
			"type": "continuous",
			"data": _continuous_colormaps[name]
		}
	elif _discrete_colormaps.has(name):
		return {
			"type": "discrete", 
			"data": _discrete_colormaps[name]
		}
	else:
		push_error("Colormap '%s' not found" % name)
		return {}

# Get list of available colormap names
static func get_available_colormaps() -> Array:
	_init_colormaps()
	var names = []
	names.append_array(_continuous_colormaps.keys())
	names.append_array(_discrete_colormaps.keys())
	return names

# Sample a continuous colormap at a given position (0.0 to 1.0)
static func sample_colormap(name: String, t: float, a: float) -> Color:
	var cmap = get_colormap(name)
	if cmap.is_empty():
		return Color.WHITE
		
	t = clamp(t, 0.0, 1.0)
	
	if cmap.type == "discrete":
		var colors = cmap.data as Array
		var idx = int(t * (colors.size() - 1))
		var color = colors[idx]
		color[3] = a
		print('discrete' + str(color))
		return color
	elif cmap.type == "continuous":
		var data = cmap.data as Dictionary
		var r = _interpolate_channel(data.red, t)
		var g = _interpolate_channel(data.green, t) 
		var b = _interpolate_channel(data.blue, t)
		print('continuous' + str(Color(r, g, b, a)))
		return Color(r, g, b, a)
	
	return Color.WHITE

# Helper function to interpolate a color channel
static func _interpolate_channel(segments: Array, t: float) -> float:
	if segments.size() == 0:
		return 0.0
	
	# Find the right segment
	for i in range(segments.size() - 1):
		var seg1 = segments[i] as Array
		var seg2 = segments[i + 1] as Array
		
		if t >= seg1[0] and t <= seg2[0]:
			# Linear interpolation between segments
			var alpha = (t - seg1[0]) / (seg2[0] - seg1[0])
			return lerp(seg1[2], seg2[1], alpha)  # seg1[2] is right value, seg2[1] is left value
	
	# If t is beyond the last segment, return the last value
	var last_seg = segments[-1] as Array
	return last_seg[2]

# Generate a gradient texture from a colormap
static func create_gradient_texture(name: String, width: int = 256, height: int = 1) -> ImageTexture:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	for x in range(width):
		var t = float(x) / float(width - 1)
		var color = sample_colormap(name, t, (x/255)**(1/4))
		
		for y in range(height):
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	return texture

# Get a color palette from a colormap (useful for discrete plotting)
static func get_palette(name: String, n_colors: int = 10) -> Array:
	var colors = []
	for i in range(n_colors):
		var t = float(i) / float(n_colors - 1) if n_colors > 1 else 0.0
		colors.append(sample_colormap(name, t, 1))
	return colors

# Create a GradientTexture1D from a colormap
static func create_gradient_texture_1d(name: String, resolution: int = 256) -> GradientTexture1D:
	var gradient = Gradient.new()
	var gradient_texture = GradientTexture1D.new()
	
	# Set gradient points (Godot Gradient supports up to 32 points by default)
	# If we need more resolution, we'll sample fewer points strategically
	var max_points = 32
	var step = max(1, resolution / max_points)
	
	#gradient.clear()
	for i in range(0, resolution, step):
		var t = float(i) / float(resolution - 1)
		var color = sample_colormap(name, t, pow(t, .25))
		gradient.add_point(t, color)
	
	# Ensure we always have the end point
	if gradient.get_offset(gradient.get_point_count() - 1) < 1.0:
		gradient.add_point(1.0, sample_colormap(name, 1.0, 1))
	
	gradient_texture.gradient = gradient
	gradient_texture.width = resolution
	
	return gradient_texture
