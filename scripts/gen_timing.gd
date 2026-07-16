class_name GenTiming
## Coarse end-to-end timing marks for the AI Generate flow.
## Single-run, order-of-magnitude instrumentation. Grep the Godot console
## output for [GENTIMING]. reset() is called at prompt submit; mark() prints
## elapsed time since reset and since the previous mark.

static var _t0: int = -1
static var _last: int = -1


static func reset() -> void:
	_t0 = -1
	_last = -1


static func mark(label: String) -> void:
	var now := Time.get_ticks_msec()
	if _t0 < 0:
		_t0 = now
		_last = now
	print("[GENTIMING] %-48s t=%9.3fs (+%.3fs)" % [
		label, (now - _t0) / 1000.0, (now - _last) / 1000.0
	])
	_last = now
