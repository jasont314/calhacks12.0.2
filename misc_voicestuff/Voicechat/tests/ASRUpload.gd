# ASRClient.gd
extends Node

const ASR_URL := "https://api.fish.audio/v1/asr"

signal asr_ok(text)
signal asr_error(message)

func send_asr_request(api_key: String, wav_path: String, language := "en", ignore_timestamps := false) -> void:
	# Read file
	var file_bytes := FileAccess.get_file_as_bytes(wav_path)
	if file_bytes.is_empty():
		emit_signal("asr_error", "Could not read file: %s" % wav_path)
		return

	# Build multipart/form-data body
	var boundary := "--------------------------" + str(Time.get_ticks_usec())
	var crlf := "\r\n"

	func add_text_field(name: String, value: String) -> PackedByteArray:
		var part := ""
		part += "--%s%s" % [boundary, crlf]
		part += 'Content-Disposition: form-data; name="%s"%s' % [name, crlf]
		part += crlf
		part += "%s%s" % [value, crlf]
		return part.to_utf8_buffer()

	func add_file_field(name: String, filename: String, bytes: PackedByteArray, mime := "audio/wav") -> PackedByteArray:
		var head := ""
		head += "--%s%s" % [boundary, crlf]
		head += 'Content-Disposition: form-data; name="%s"; filename="%s"%s' % [name, filename, crlf]
		head += "Content-Type: %s%s" % [mime, crlf]
		head += crlf
		var segment := PackedByteArray()
		segment.append_array(head.to_utf8_buffer())
		segment.append_array(bytes)
		segment.append_array(crlf.to_utf8_buffer())
		return segment

	var body := PackedByteArray()
	body.append_array(add_text_field("language", language))
	body.append_array(add_text_field("ignore_timestamps", ignore_timestamps ? "true" : "false"))
	body.append_array(add_file_field("audio", wav_path.get_file(), file_bytes, "audio/wav"))
	body.append_array(("--%s--%s" % [boundary, crlf]).to_utf8_buffer())

	# Prepare HTTPRequest node
	var http := HTTPRequest.new()
	add_child(http)

	# One-shot completion connection
	http.request_completed.connect(_on_http_completed.bind(http), CONNECT_ONE_SHOT)

	var headers := [
		"Authorization: Bearer " + api_key,
		"Content-Type: multipart/form-data; boundary=" + boundary
	]

	# Use request_raw for binary body
	var err := http.request_raw(ASR_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		emit_signal("asr_error", "request_raw() failed: %s" % str(err))
		http.queue_free()


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("asr_error", "HTTP error: %s" % str(result))
		return
	if response_code < 200 or response_code >= 300:
		emit_signal("asr_error", "ASR HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		return
	var txt := body.get_string_from_utf8()
	var json := JSON.new()
	var parse_ok := json.parse(txt)
	if parse_ok != OK:
		emit_signal("asr_error", "Parse error: " + txt)
		return
	var data := json.data
	# Adjust field names to whatever the API returns; commonly something like data["text"]
	if data.has("text"):
		emit_signal("asr_ok", String(data["text"]))
	else:
		emit_signal("asr_error", "No 'text' in response: " + txt)
