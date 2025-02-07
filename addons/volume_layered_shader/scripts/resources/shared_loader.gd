extends Node


func load_into(image:Image, buf:PackedByteArray, suffix:String):
    match suffix:
        'png':
            image.load_png_from_buffer(buf)
        'jpg':
            image.load_jpg_from_buffer(buf)
        'jpeg':
            image.load_jpg_from_buffer(buf)
        _:
            push_error('Unhandled extension in zip: ' + suffix)
            return
    print_debug('loaded: ' + suffix)
