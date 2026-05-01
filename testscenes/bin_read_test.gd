extends Node3D

@export var field_file: String
@export var metadata_file: String

@onready var mesh = $MeshInstance3D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE 
	read_bin() # Replace with function body.

func read_bin():
	# the json contains the (x, y, z, c, t) values, so we need to grab those from json
	var json_as_text = FileAccess.get_file_as_string(metadata_file)
	var metadata = JSON.parse_string(json_as_text)
	var shape = Vector3(metadata['shape']['X'], metadata['shape']['Y'], metadata['shape']['Z'])
	print(shape)
	
	# Open the binary file
	var file = FileAccess.open(field_file, FileAccess.READ)
	var data = file.get_buffer(file.get_length())
	file.close()
	
	var images     = Array()
	var frame_size = shape[0] * shape[1]
	for z in range(shape[2]):
		var image = Image.new()
		var start = z * frame_size
		image.set_data(shape[0], shape[1], false, Image.FORMAT_L8, data.slice(start, start+frame_size))
		images.append(image)

	# Create a 3D texture
	var bin_texture = ImageTexture3D.new()
	bin_texture.create(Image.FORMAT_L8, shape[0], shape[1], shape[2], false, images)
	#bin_texture.init_ref()
	#mesh.texture = bin_texture

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
