## HTTP-based data source for Ascribe-Link.
## Sends processing requests via HTTP POST and receives mesh data back.
class_name HTTPSource
extends DataSource

var _http_request: HTTPRequest
var _base_url: String
var _request_payload: Dictionary
var _is_waiting: bool = false

## Create an HTTP source pointing at an Ascribe-Link server.
func _init(base_url: String = "http://localhost:8000") -> void:
	_base_url = base_url.rstrip("/")


## Attach to the scene tree (required for HTTPRequest to work).
func setup(parent: Node) -> void:
	if _http_request != null:
		return
	_http_request = HTTPRequest.new()
	_http_request.request_completed.connect(_on_request_completed)
	parent.add_child(_http_request)


## Set the processing request payload.
## payload should have: function_name, args (optional), kwargs (optional)
func set_request(payload: Dictionary) -> void:
	_request_payload = payload


func is_available() -> bool:
	return _http_request != null and not _is_waiting


func fetch() -> void:
	if _http_request == null:
		source_error.emit("HTTPSource not set up — call setup(parent_node) first")
		return
	if _is_waiting:
		source_error.emit("Request already in progress")
		return

	_is_waiting = true
	var url = _base_url + "/api/processing/invoke"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(_request_payload)

	var error = _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_is_waiting = false
		source_error.emit("HTTP request failed to start: %s" % error_string(error))


func cancel() -> void:
	if _http_request and _is_waiting:
		_http_request.cancel_request()
		_is_waiting = false


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_waiting = false

	if result != HTTPRequest.RESULT_SUCCESS:
		source_error.emit("HTTP request failed: result=%d" % result)
		return

	if response_code < 200 or response_code >= 300:
		var error_text = body.get_string_from_utf8()
		source_error.emit("HTTP %d: %s" % [response_code, error_text])
		return

	var json_string = body.get_string_from_utf8()
	var parsed = JSON.parse_string(json_string)
	if parsed == null:
		source_error.emit("Invalid JSON response from server")
		return

	data_available.emit(parsed)
