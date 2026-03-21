## Client for Ascribe-Link HTTP API.
## Handles specimen catalog and function listing (non-pipeline operations).
class_name AscribeLinkClient
extends RefCounted

signal specimens_loaded(specimens: Array)
signal functions_loaded(functions: Array)
signal request_error(error: String)

var _base_url: String
var _parent: Node
var _specimens_request: HTTPRequest
var _functions_request: HTTPRequest


func _init(base_url: String = "http://localhost:8000") -> void:
	_base_url = base_url.rstrip("/")


## Attach to a scene tree node (required for HTTPRequest to work).
func setup(parent: Node) -> void:
	_parent = parent

	_specimens_request = HTTPRequest.new()
	_specimens_request.request_completed.connect(_on_specimens_completed)
	_parent.add_child(_specimens_request)

	_functions_request = HTTPRequest.new()
	_functions_request.request_completed.connect(_on_functions_completed)
	_parent.add_child(_functions_request)


## Fetch the list of curated specimens.
func fetch_specimens() -> void:
	if _specimens_request == null:
		request_error.emit("Client not set up")
		return
	
	# Set a reasonable timeout (5 seconds) for server connection
	_specimens_request.timeout = 5.0
	
	var url = _base_url + "/api/specimens/"
	print("AscribeLinkClient: Requesting ", url)
	var error = _specimens_request.request(url)
	if error != OK:
		push_error("Failed to start specimens request: %s (error code: %d)" % [error_string(error), error])
		request_error.emit("Failed to start specimens request: %s" % error_string(error))
	else:
		print("AscribeLinkClient: Request started successfully")


## Fetch the list of registered processing functions.
func fetch_functions() -> void:
	if _functions_request == null:
		request_error.emit("Client not set up")
		return
	var url = _base_url + "/api/processing/functions"
	var error = _functions_request.request(url)
	if error != OK:
		request_error.emit("Failed to start functions request: %s" % error_string(error))


## Get the URL to download specimen data directly.
func get_specimen_data_url(specimen_id: String) -> String:
	return _base_url + "/api/specimens/" + specimen_id + "/data"


## Get the URL for a specimen thumbnail.
func get_specimen_thumbnail_url(specimen_id: String) -> String:
	return _base_url + "/api/specimens/" + specimen_id + "/thumbnail"


func _on_specimens_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("AscribeLinkClient: Request completed - result=%d, response_code=%d, body_size=%d" % [result, response_code, body.size()])
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Specimens request failed: result=%d (%s)" % [result, _get_result_string(result)])
		request_error.emit("Specimens request failed: result=%d" % result)
		return
	if response_code != 200:
		push_error("Specimens HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		request_error.emit("Specimens HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		return

	var body_str = body.get_string_from_utf8()
	print("AscribeLinkClient: Response body: ", body_str.substr(0, 200))  # First 200 chars
	
	var parsed = JSON.parse_string(body_str)
	if parsed == null:
		push_error("Invalid JSON in specimens response")
		request_error.emit("Invalid JSON in specimens response")
		return

	specimens_loaded.emit(parsed)


func _get_result_string(result: int) -> String:
	match result:
		0: return "SUCCESS"
		1: return "CHUNKED_BODY_SIZE_MISMATCH"
		2: return "CANT_CONNECT"
		3: return "CANT_RESOLVE"
		4: return "CONNECTION_ERROR"
		5: return "TLS_HANDSHAKE_ERROR"
		6: return "NO_RESPONSE"
		7: return "BODY_SIZE_LIMIT_EXCEEDED"
		8: return "BODY_DECOMPRESS_FAILED"
		9: return "REQUEST_FAILED"
		10: return "DOWNLOAD_FILE_CANT_OPEN"
		11: return "DOWNLOAD_FILE_WRITE_ERROR"
		12: return "REDIRECT_LIMIT_REACHED"
		13: return "TIMEOUT"
		_: return "UNKNOWN"


func _on_functions_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		request_error.emit("Functions request failed: result=%d" % result)
		return
	if response_code != 200:
		request_error.emit("Functions HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		request_error.emit("Invalid JSON in functions response")
		return

	functions_loaded.emit(parsed)


## Fetch full metadata for a specific specimen (includes schema for dynamic specimens).
## Returns a Dictionary via await on the returned signal awaiter.
func fetch_specimen_metadata(specimen_id: String) -> Dictionary:
	var http = HTTPRequest.new()
	_parent.add_child(http)
	
	var url = _base_url + "/api/specimens/" + specimen_id
	var error = http.request(url)
	if error != OK:
		http.queue_free()
		return {}
	
	var response = await http.request_completed
	http.queue_free()
	
	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return {}
	
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		return {}
	
	return parsed


## Invoke a processing function with parameters and return the result.
## Returns a Dictionary with 'type' field ("mesh", "volume", etc.) via await.
## room_id is used for multiplayer caching (defaults to "ascribe").
func invoke_processing_function(function_name: String, params: Dictionary, room_id: String = "ascribe") -> Dictionary:
	var http = HTTPRequest.new()
	_parent.add_child(http)
	
	var url = _base_url + "/api/processing/invoke"
	var body = JSON.stringify({
		"function_name": function_name,
		"args": [],
		"kwargs": params,
		"room_id": room_id
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		return {"error": "Failed to start request"}
	
	var response = await http.request_completed
	http.queue_free()
	
	var result: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Request failed: result=%d" % result}
	if response_code != 200:
		return {"error": "HTTP %d: %s" % [response_code, response_body.get_string_from_utf8()]}
	
	var parsed = JSON.parse_string(response_body.get_string_from_utf8())
	if parsed == null:
		return {"error": "Invalid JSON in response"}
	
	return parsed
