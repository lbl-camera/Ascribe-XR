extends Node

var supported_image_file_formats: Array[String] = [
												  "bmp",
												  "dds",
												  "exr",
												  "hdr",
												  "jpg",
												  "jpeg",
												  "png",
												  "tga",
												  "svg",
												  "webp"
												  ]

func load_into(image: Image, buf: PackedByteArray, suffix: String):
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
