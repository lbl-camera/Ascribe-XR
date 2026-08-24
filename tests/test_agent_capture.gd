extends GdUnitTestSuite


static func _gradient_image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, Color(float(x) / w, float(y) / h, 0.5))
	return img


func test_process_image_downscales_keeping_aspect():
	var img := _gradient_image(2048, 1024)
	var raw_size := img.get_data().size()
	var jpeg := AgentCapture.process_image(img, 1024, 0.75)

	assert_that(jpeg.is_empty()).is_false()
	assert_that(jpeg.size()).is_less(raw_size)

	var decoded := Image.new()
	var err := decoded.load_jpg_from_buffer(jpeg)
	assert_that(err).is_equal(OK)
	assert_that(decoded.get_width()).is_equal(1024)
	assert_that(decoded.get_height()).is_equal(512)


func test_process_image_does_not_upscale_smaller_image():
	var img := _gradient_image(800, 600)
	var jpeg := AgentCapture.process_image(img, 1024, 0.75)

	assert_that(jpeg.is_empty()).is_false()

	var decoded := Image.new()
	var err := decoded.load_jpg_from_buffer(jpeg)
	assert_that(err).is_equal(OK)
	assert_that(decoded.get_width()).is_equal(800)
	assert_that(decoded.get_height()).is_equal(600)


func test_process_image_portrait_preserves_aspect():
	var img := _gradient_image(1024, 2048)
	var jpeg := AgentCapture.process_image(img, 1024, 0.75)

	var decoded := Image.new()
	var err := decoded.load_jpg_from_buffer(jpeg)
	assert_that(err).is_equal(OK)
	assert_that(decoded.get_width()).is_equal(512)
	assert_that(decoded.get_height()).is_equal(1024)
