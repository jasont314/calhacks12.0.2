# res://scripts/autoload/jllm_api.gd
extends Node

signal response_received(text: String)
signal api_error(error_message: String)

const API_URL = "https://janitorai.com/hackathon/completions"
const API_KEY = "calhacks2047"  # Get from Slack

# Performance optimization
var request_cache: Dictionary = {}  # Cache responses
var pending_requests: Dictionary = {}  # Deduplicate simultaneous requests

func _ready():
	print("✅ JLLM API initialized")

func send_message(
	system_prompt: String,
	messages: Array,
	max_tokens: int = 150
) -> String:
	"""
    Send request to JLLM API (OpenAI-compatible format)
    
    Args:
        system_prompt: System message
        messages: Array of {role, content}
        max_tokens: Max response length
	"""
	
	# Build cache key (for duplicate prevention)
	var cache_key = _build_cache_key(system_prompt, messages)
	
	# Check cache first
	if request_cache.has(cache_key):
		var cached = request_cache[cache_key]
		print("💾 Using cached response")
		response_received.emit(cached)
		return cached
	
	# Check if identical request is pending
	if pending_requests.has(cache_key):
		print("⏳ Waiting for pending request...")
		await pending_requests[cache_key]
		return request_cache.get(cache_key, "")
	
	# Create pending signal
	var pending_signal = Signal()
	pending_requests[cache_key] = pending_signal
	
	# Build request body (OpenAI format)
	var body = {
		"model": "ignored",  # JLLM forces their model
		"messages": [
			{
				"role": "system",
				"content": system_prompt
			}
		],
		"max_tokens": max_tokens,
		"temperature": 0.8,  # Slightly creative
		"stream": false
	}
	
	# Add conversation messages
	body["messages"].append_array(messages)
	
	# Create HTTP request
	var http = HTTPRequest.new()
	add_child(http)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + API_KEY
	]
	
	print("📤 Sending to JLLM...")
	var start_time = Time.get_ticks_msec()
	
	var error = http.request(
		API_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	
	if error != OK:
		push_error("HTTP request failed: " + str(error))
		http.queue_free()
		pending_requests.erase(cache_key)
		api_error.emit("Network error")
		return "Error: Network request failed"
	
	# Wait for response
	var response = await http.request_completed
	var response_code = response[1]
	var response_body = response[3]
	
	var elapsed = Time.get_ticks_msec() - start_time
	print("📥 JLLM responded in %d ms" % elapsed)
	
	http.queue_free()
	
	# Handle response
	if response_code != 200:
		push_error("❌ API error: " + str(response_code))
		var error_body = response_body.get_string_from_utf8()
		push_error("Response: " + error_body)
		pending_requests.erase(cache_key)
		api_error.emit("API error: " + str(response_code))
		return "Error: API request failed"
	
	# Parse response (OpenAI format)
	var json_string = response_body.get_string_from_utf8()
	var json = JSON.parse_string(json_string)
	
	if json and json.has("choices") and json["choices"].size() > 0:
		var reply = json["choices"][0]["message"]["content"]
		
		# Cache the response
		request_cache[cache_key] = reply
		
		# Notify pending requests
		pending_requests.erase(cache_key)
		
		response_received.emit(reply)
		return reply
	else:
		push_error("❌ Unexpected API response format")
		push_error("Response: " + json_string)
		pending_requests.erase(cache_key)
		api_error.emit("Could not parse response")
		return "Error: Unexpected response format"

func _build_cache_key(system: String, messages: Array) -> String:
	"""Build cache key from request"""
	var key_parts = [system]
	
	# Only use last 5 messages for cache key (recent context)
	var recent = messages.slice(-5) if messages.size() > 5 else messages
	
	for msg in recent:
		key_parts.append(msg.get("role", "") + ":" + msg.get("content", ""))
	
	return str(key_parts).md5_text()

func clear_cache():
	"""Clear response cache (call periodically)"""
	request_cache.clear()
	print("🗑️ Cleared JLLM response cache")
