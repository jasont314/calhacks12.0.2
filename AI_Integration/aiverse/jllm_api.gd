extends Node

signal reply_ready(text: String)
signal api_error(msg: String)

const API_URL := "https://janitorai.com/hackathon/completions"
const API_KEY := "calhacks2047" # local only, don't commit this

func send_message(system_prompt: String, messages: Array, max_tokens: int = 150) -> void:
	# Build request body
	var body := {
		"model": "ignored",
		"messages": [
			{ "role": "system", "content": system_prompt }
		],
		"max_tokens": max_tokens,
		"temperature": 0.8,
		"stream": false # we ask for false but Janitor still streams
	}
	body["messages"].append_array(messages)

	# Create an HTTPRequest for THIS call
	var http := HTTPRequest.new()
	add_child(http)

	# When it's done, call _on_http_completed(...) once
	http.request_completed.connect(_on_http_completed.bind(http), CONNECT_ONE_SHOT)

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + API_KEY
	]

	var err := http.request(
		API_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if err != OK:
		emit_signal("api_error", "request() failed: " + str(err))
		http.queue_free()


func _on_http_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest
) -> void:
	_handle_response(http, response_code, body)


func _handle_response(http: HTTPRequest, response_code: int, raw_bytes: PackedByteArray) -> void:
	var body_text := raw_bytes.get_string_from_utf8()
	http.queue_free()

	# Debug so we can see what the server actually sent
	# print("[JLLM] response_code=", response_code)
	# print("[JLLM] raw body:\n", body_text)

	# Connection / auth / server error case
	if response_code != 200:
		emit_signal("api_error", "HTTP " + str(response_code) + " body: " + body_text)
		return

	# CASE A: Janitor streamed chunks (what you're seeing now)
	# Starts with "data:" lines, not valid JSON
	if body_text.begins_with("data:"):
		var reply_streamed := _parse_sse_chunks(body_text)
		if reply_streamed == "":
			emit_signal("api_error", "SSE parse failed or empty reply:\n" + body_text)
			return

		emit_signal("reply_ready", reply_streamed)
		return

	# CASE B: Janitor gave us normal OpenAI-style JSON (sometimes happens in other configs)
	var reply_normal := _parse_normal_json(body_text)
	if reply_normal == "":
		emit_signal("api_error", "Couldn't extract reply from non-stream JSON:\n" + body_text)
		return

	emit_signal("reply_ready", reply_normal)


#
# Helper: parse normal non-stream JSON
#
# Expected shape:
# {
#    "choices": [
#      {
#        "message": {
#          "role": "assistant",
#          "content": "the reply text"
#        }
#      }
#    ]
# }
#
func _parse_normal_json(body_text: String) -> String:
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""

	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		return ""

	if typeof(choices[0]) != TYPE_DICTIONARY:
		return ""

	var msg_block: Dictionary = choices[0].get("message", {})
	if typeof(msg_block) != TYPE_DICTIONARY:
		return ""

	if not msg_block.has("content"):
		return ""

	return String(msg_block["content"])


#
# Helper: parse streamed "data:" chunks (Server-Sent Events style)
#
# Looks like:
#   data: {"choices":[{"delta":{"content":""}}]}
#   data: {"choices":[{"delta":{"content":"Well"}}]}
#   data: {"choices":[{"delta":{"content":", depends on the"}}]}
#   data: [DONE]
#
# We just stitch together all delta.content values.
#
func _parse_sse_chunks(raw_text: String) -> String:
	var full_reply := ""

	# Split entire body into individual lines
	var lines: Array = raw_text.split("\n")

	for line_any in lines:
		var line_str := String(line_any).strip_edges()

		# skip junk/empty lines
		if line_str == "" or not line_str.begins_with("data:"):
			continue

		# remove leading "data:" (5 chars), then trim again
		var payload := line_str.substr(5).strip_edges()

		# end of stream
		if payload == "[DONE]":
			break

		# now payload SHOULD be json like:
		#   {"choices":[{"delta":{"content":"Well"}}]}
		var chunk_json: Variant = JSON.parse_string(payload)
		if typeof(chunk_json) != TYPE_DICTIONARY:
			continue

		# grab choices[0].delta.content
		var choices_local: Array = chunk_json.get("choices", [])
		if choices_local.is_empty():
			continue

		var first_choice = choices_local[0]
		if typeof(first_choice) != TYPE_DICTIONARY:
			continue

		var delta_dict = first_choice.get("delta", {})
		if typeof(delta_dict) == TYPE_DICTIONARY and delta_dict.has("content"):
			full_reply += String(delta_dict["content"])

	return full_reply
