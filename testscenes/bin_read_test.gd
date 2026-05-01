extends Node3D

@export var field_file: String
@export var metadata_file: String
@export var timestep: int = 0

@export_enum("magnitude", "mx", "my", "mz")
var channel_mode: String = "magnitude"

@onready var mesh: MeshInstance3D = $MeshInstance3D

var X: int
var Y: int
var Z: int
var C: int
var T: int

var field: PackedFloat32Array
var volume_texture: ImageTexture3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	load_metadata()
	load_field()
	update_volume_texture(timestep)

func load_metadata() -> void:
	var json_as_text := FileAccess.get_file_as_string(metadata_file)
	var metadata = JSON.parse_string(json_as_text)

	X = int(metadata["shape"]["X"])
	Y = int(metadata["shape"]["Y"])
	Z = int(metadata["shape"]["Z"])
	C = int(metadata["shape"]["components"])
	T = int(metadata["shape"]["T"])

	print("Loaded shape: ", X, " ", Y, " ", Z, " C=", C, " T=", T)

func load_field() -> void:
	var file := FileAccess.open(field_file, FileAccess.READ)
	if file == null:
		push_error("Could not open field file: " + field_file)
		return

	var float_count := X * Y * Z * C * T

	field = PackedFloat32Array()
	field.resize(float_count)

	for i in range(float_count):
		field[i] = file.get_float()

	file.close()
	print("Loaded floats: ", field.size())

func idx(x: int, y: int, z: int, c: int, t: int) -> int:
	# Python wrote shape (X, Y, Z, C, T) with NumPy C-order
	return (((((x * Y) + y) * Z + z) * C + c) * T + t)

func get_component(x: int, y: int, z: int, c: int, t: int) -> float:
	return field[idx(x, y, z, c, t)]

func get_scalar(x: int, y: int, z: int, t: int) -> float:
	var mx := get_component(x, y, z, 0, t)
	var my := get_component(x, y, z, 1, t)
	var mz := get_component(x, y, z, 2, t)

	match channel_mode:
		"mx":
			return mx * 0.5 + 0.5
		"my":
			return my * 0.5 + 0.5
		"mz":
			return mz * 0.5 + 0.5
		_:
			return sqrt(mx * mx + my * my + mz * mz)

func update_volume_texture(t: int) -> void:
	t = clamp(t, 0, T - 1)

	var values := PackedFloat32Array()
	values.resize(X * Y * Z)

	var min_v := INF
	var max_v := -INF

	for z in range(Z):
		for y in range(Y):
			for x in range(X):
				var v := get_scalar(x, y, z, t)
				var flat := x + X * (y + Y * z)
				values[flat] = v
				min_v = min(min_v, v)
				max_v = max(max_v, v)

	var images: Array[Image] = []

	for z in range(Z):
		var bytes := PackedByteArray()
		bytes.resize(X * Y)

		for y in range(Y):
			for x in range(X):
				var flat := x + X * (y + Y * z)
				var v := values[flat]

				var normalized := 0.0
				if max_v > min_v:
					normalized = (v - min_v) / (max_v - min_v)

				bytes[x + y * X] = int(clamp(normalized * 255.0, 0.0, 255.0))

		var img := Image.create_from_data(X, Y, false, Image.FORMAT_L8, bytes)

		images.append(img)

	volume_texture = ImageTexture3D.new()
	volume_texture.create(Image.FORMAT_L8, X, Y, Z, false, images)

	var mat := mesh.get_active_material(0) as ShaderMaterial
	mat.set_shader_parameter("texture_volume", volume_texture)

	print("Updated 3D texture for timestep ", t)
