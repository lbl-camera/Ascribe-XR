@tool
extends Specimen

@export_file("*.zip", "*.bin") var data_file: String:
    set(value):
        if value:
            var volume_texture: ImageTexture3D = make_texture(value)
            $XRToolsPickable2/VolumeLayeredShader.texture = volume_texture

func texture_from_bin(data_file: String) -> ImageTexture3D:
    var shape: Vector3i = Vector3i(256, 256, 10)

    # Open the binary file
    var file: FileAccess      = FileAccess.open(data_file, FileAccess.READ)
    var data: PackedByteArray = file.get_buffer(file.get_length())
    file.close()

    var images: Array   = Array()
    var frame_size: int = shape[0] * shape[1]
    for z in range(shape[2]):
        var image = Image.new()
        var start = z * frame_size
        image.set_data(shape[0], shape[1], false, Image.FORMAT_L8, data.slice(start,start+frame_size))
        images.append(image)

    # Create a 3D texture
    var bin_texture = ImageTexture3D.new()
    bin_texture.create(Image.FORMAT_L8, shape[0], shape[1], shape[2], false, images)
    #bin_texture.init_ref()
    return bin_texture

func texture_from_zip(data_file) -> ZippedImageArchiveRFTexture3D:
    var texture: ZippedImageArchiveRFTexture3D = ZippedImageArchiveRFTexture3D.new()
    var archive = ZippedImageArchive_RF_3D.new()
    archive.zip_file = data_file
    texture.archive = archive
    print_debug('archive:', archive)
    return texture

func make_texture(data_file: String) -> Resource:
    if data_file.ends_with('.bin'):
        return texture_from_bin(data_file)
    elif data_file.ends_with('.zip'):
        return texture_from_zip(data_file)
    return null

#func _enter_tree() -> void:
    #if data_file:
        #var volume_texture: ImageTexture3D = make_texture(data_file)
        #$XRToolsPickable2/VolumeLayeredShader.texture = volume_texture
