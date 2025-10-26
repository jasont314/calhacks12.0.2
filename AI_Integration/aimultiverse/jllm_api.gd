extends Node
class_name JLLMApi

signal reply_ready(text: String)
signal api_error(msg: String)

const API_URL := "https://janitorai.com/hackathon/completions"
const API_KEY := "calhacks2047" # local only – don't commit real key

func send_message(system_prompt: String, messages: Array, max_tokens: int = 150) -> void:
	# Build request body in OpenAI-ish format
	var body := {
		"model": "ignored",
		"messages": [
			{ "role": "system", "content": system_prompt }
		],
		"max_tokens": max_tokens,
		"temperature": 0.8,
		"stream": false # we ask false, but API may still stream SSE
	}
	body["messages"].append_array(messages)

	var http := HTTPRequest.new()
	add_child(http)

	# fire once
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
	_handle_response(response_code, body, http)


func _handle_response(response_code: int, raw_bytes: PackedByteArray, http: HTTPRequest) -> void:
	var body_text := raw_bytes.get_string_from_utf8()
	http.queue_free()

	# Non-200 -> fail
	if response_code != 200:
		emit_signal("api_error", "HTTP " + str(response_code) + " body: " + body_text)
		return

	# CASE A: SSE-style streaming (starts with "data:")
	if body_text.begins_with("data:"):
		var reply_streamed := _parse_sse_chunks(body_text)
		if reply_streamed == "":
			emit_signal("api_error", "SSE parse failed:\n" + body_text)
			return
		emit_signal("reply_ready", reply_streamed)
		return

	# CASE B: "normal" JSON with choices[0].message.content
	var reply_normal := _parse_normal_json(body_text)
	if reply_normal == "":
		emit_signal("api_error", "Couldn't parse normal JSON:\n" + body_text)
		return

	emit_signal("reply_ready", reply_normal)


func _parse_normal_json(body_text: String) -> String:
	# Expected:
	# {
	#   "choices":[
	#     {"message":{"role":"assistant","content":"the reply text"}}
	#   ]
	# }
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""

	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		return ""

	var first_choice = choices[0]
	if typeof(first_choice) != TYPE_DICTIONARY:
		return ""

	var msg_block: Dictionary = first_choice.get("message", {})
	if typeof(msg_block) != TYPE_DICTIONARY:
		return ""

	if not msg_block.has("content"):
		return ""

	return String(msg_block["content"])


func _parse_sse_chunks(raw_text: String) -> String:
	# Looks like:
	# data: {"choices":[{"delta":{"content":"Hello"}}]}
	# data: {"choices":[{"delta":{"content":" world"}}]}
	# data: [DONE]
	var full_reply := ""
	var lines: Array = raw_text.split("\n")

	for line_any in lines:
		var line_str := String(line_any).strip_edges()
		if line_str == "" or not line_str.begins_with("data:"):
			continue

		var payload := line_str.substr(5).strip_edges()  # remove "data:"
		if payload == "[DONE]":
			break

		var chunk_json: Variant = JSON.parse_string(payload)
		if typeof(chunk_json) != TYPE_DICTIONARY:
			continue

		var choices_piece: Array = chunk_json.get("choices", [])
		if choices_piece.is_empty():
			continue

		var first_choice = choices_piece[0]
		if typeof(first_choice) != TYPE_DICTIONARY:
			continue

		var delta_dict = first_choice.get("delta", {})
		if typeof(delta_dict) == TYPE_DICTIONARY and delta_dict.has("content"):
			full_reply += String(delta_dict["content"])

	return full_reply
