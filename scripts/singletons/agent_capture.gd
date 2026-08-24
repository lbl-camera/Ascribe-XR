## AgentCapture -- static helper for capturing and encoding the current
## viewport frame for the conversational agent's vision tool. `process_image`
## is pure (testable without a scene tree); `capture` needs a Viewport.
class_name AgentCapture
extends RefCounted


## Downscale `img` (in place, on a duplicate) so that max(width, height) does
## not exceed `max_dim`, preserving aspect ratio. Never upscales. Returns a
## JPEG-encoded buffer at the given `quality` (0.0-1.0).
static func process_image(img: Image, max_dim: int = 1024, quality: float = 0.75) -> PackedByteArray:
	var out: Image = img.duplicate()
	var w: int = out.get_width()
	var h: int = out.get_height()
	var largest: int = max(w, h)
	if largest > max_dim:
		var scale := float(max_dim) / float(largest)
		var new_w: int = maxi(1, roundi(w * scale))
		var new_h: int = maxi(1, roundi(h * scale))
		out.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)
	return out.save_jpg_to_buffer(quality)


## Await the next fully-rendered frame of `viewport`, grab its image, and
## return a downscaled JPEG buffer. Must be called from a node context
## (e.g. `await AgentCapture.capture(get_viewport())`).
static func capture(viewport: Viewport, max_dim: int = 1024) -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	return process_image(img, max_dim)
