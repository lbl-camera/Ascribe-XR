extends Node3D

@export var data_size: Vector3i = Vector3i(128, 128, 128):
	set(value):
		data_size = value
		_regenerate()

@export var volume_visible: bool = true:
	set(value):
		volume_visible = value
		if _volume:
			_volume.visible = value

@onready var _volume: VolumeLayers = $VolumeLayeredShader


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_volume.visible = volume_visible
	_regenerate()


func _regenerate() -> void:
	if not _volume:
		return
	_volume.texture = _make_noise_texture(data_size)


static func _make_noise_texture(size: Vector3i) -> ImageTexture3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 42
	noise.frequency = 0.03

	var images: Array[Image] = []
	for z in range(size.z):
		var bytes := PackedByteArray()
		bytes.resize(size.x * size.y)
		for y in range(size.y):
			for x in range(size.x):
				var n := noise.get_noise_3d(float(x), float(y), float(z))
				bytes[y * size.x + x] = int(clamp((n + 1.0) * 0.5 * 255.0, 0.0, 255.0))
		images.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, bytes))

	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_L8, size.x, size.y, size.z, false, images)
	return tex
