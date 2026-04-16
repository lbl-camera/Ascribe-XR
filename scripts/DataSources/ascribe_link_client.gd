## Client for Ascribe-Link HTTP API.
## Handles specimen catalog and function listing (non-pipeline operations).
class_name AscribeLinkClient
extends RefCounted

signal specimens_loaded(specimens: Array)
signal functions_loaded(functions: Array)
signal request_error(error: String)
signal job_progress(text: String)
signal job_complete(result: Dictionary)
signal job_error(error: String)

var _base_url: String
var _parent: Node
var _specimens_request: HTTPRequest
var _functions_request: HTTPRequest
var _current_job_id: String = ""


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


## Run a dynamic specimen as a job: POST /start, poll /progress, GET /result.
## Authority should be the only caller. Results are emitted via signals.
func run_job(specimen_id: String, params: Dictionary, room_id: String = "ascribe") -> void:
	if _parent == null:
		job_error.emit("Client not set up")
		return

	# --- 1. POST /start ---
	var start_http := HTTPRequest.new()
	_parent.add_child(start_http)
	start_http.timeout = 10.0
	var start_url := _base_url + "/api/specimens/" + specimen_id + "/start"
	var start_body := JSON.stringify({"params": params, "room_id": room_id})
	var err := start_http.request(
		start_url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		start_body,
	)
	if err != OK:
		start_http.queue_free()
		job_error.emit("Failed to POST /start: %s" % error_string(err))
		return

	var start_response = await start_http.request_completed
	start_http.queue_free()

	var start_result: int = start_response[0]
	var start_code: int = start_response[1]
	var start_payload: PackedByteArray = start_response[3]
	if start_result != HTTPRequest.RESULT_SUCCESS or start_code != 200:
		job_error.emit("POST /start failed: HTTP %d" % start_code)
		return

	var start_json: Variant = JSON.parse_string(start_payload.get_string_from_utf8())
	if not (start_json is Dictionary):
		_current_job_id = ""
		job_error.emit("Invalid /start response")
		return
	var job_id: String = start_json.get("job_id", "")
	var start_status: String = start_json.get("status", "")
	if job_id.is_empty():
		_current_job_id = ""
		job_error.emit("Missing job_id in /start response")
		return
	_current_job_id = job_id

	# --- 2. Poll /progress until status is terminal ---
	if start_status != "done":
		var last_seq := -1
		var consecutive_poll_failures := 0
		while true:
			var prog_http := HTTPRequest.new()
			_parent.add_child(prog_http)
			prog_http.timeout = 5.0
			var prog_url := "%s/api/jobs/%s/progress?since=%d" % [_base_url, job_id, last_seq]
			err = prog_http.request(prog_url)
			if err != OK:
				prog_http.queue_free()
				_current_job_id = ""
				job_error.emit("Failed to GET /progress: %s" % error_string(err))
				return
			var prog_response = await prog_http.request_completed
			prog_http.queue_free()

			var prog_result: int = prog_response[0]
			var prog_code: int = prog_response[1]
			var prog_payload: PackedByteArray = prog_response[3]
			if prog_result != HTTPRequest.RESULT_SUCCESS or prog_code != 200:
				consecutive_poll_failures += 1
				if consecutive_poll_failures >= 3:
					_current_job_id = ""
					job_error.emit(
						"Failed to GET /progress after 3 retries (HTTP %d)" % prog_code
					)
					return
				await _parent.get_tree().create_timer(0.5).timeout
				continue
			consecutive_poll_failures = 0

			var prog_json: Variant = JSON.parse_string(prog_payload.get_string_from_utf8())
			if not (prog_json is Dictionary):
				_current_job_id = ""
				job_error.emit("Invalid /progress response")
				return

			for m in prog_json.get("messages", []):
				if m is Dictionary:
					job_progress.emit(str(m.get("text", "")))
					last_seq = max(last_seq, int(m.get("seq", last_seq)))

			var st: String = prog_json.get("status", "running")
			if st == "error":
				_current_job_id = ""
				job_error.emit(str(prog_json.get("error", "unknown error")))
				return
			if st == "done":
				break

			await _parent.get_tree().create_timer(0.5).timeout

	# --- 3. GET /result ---
	var result_http := HTTPRequest.new()
	_parent.add_child(result_http)
	result_http.timeout = 10.0
	var result_url := "%s/api/jobs/%s/result" % [_base_url, job_id]
	err = result_http.request(result_url)
	if err != OK:
		result_http.queue_free()
		_current_job_id = ""
		job_error.emit("Failed to GET /result: %s" % error_string(err))
		return

	var result_response = await result_http.request_completed
	result_http.queue_free()

	var r_result: int = result_response[0]
	var r_code: int = result_response[1]
	var r_payload: PackedByteArray = result_response[3]
	if r_result != HTTPRequest.RESULT_SUCCESS or r_code != 200:
		_current_job_id = ""
		job_error.emit("GET /result failed: HTTP %d" % r_code)
		return

	var result_json: Variant = JSON.parse_string(r_payload.get_string_from_utf8())
	if not (result_json is Dictionary):
		_current_job_id = ""
		job_error.emit("Invalid /result response")
		return
	_current_job_id = ""
	job_complete.emit(result_json)


## Cancel the currently running job by sending DELETE to the server.
func cancel_current_job() -> void:
	if _parent == null or _current_job_id.is_empty():
		return
	var http := HTTPRequest.new()
	_parent.add_child(http)
	http.timeout = 5.0
	var url := "%s/api/jobs/%s" % [_base_url, _current_job_id]
	var err := http.request(url, [], HTTPClient.METHOD_DELETE)
	if err != OK:
		http.queue_free()
		return
	await http.request_completed
	http.queue_free()


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
	var payload = {
		"function_name": function_name,
		"args": [],
		"kwargs": params,
		"room_id": room_id
	}
	var body = JSON.stringify(payload)
	
	print("invoke_processing_function: URL=%s" % url)
	print("invoke_processing_function: payload=%s" % payload)
	print("invoke_processing_function: body=%s" % body)
	
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
	if response_code < 200 or response_code >= 300:
		return {"error": "HTTP %d: %s" % [response_code, response_body.get_string_from_utf8()]}
	
	var parsed = JSON.parse_string(response_body.get_string_from_utf8())
	if parsed == null:
		return {"error": "Invalid JSON in response"}
	
	return parsed
