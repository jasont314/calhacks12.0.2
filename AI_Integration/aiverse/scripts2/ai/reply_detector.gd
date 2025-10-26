# res://scripts/ai/reply_detector.gd
extends Node

signal ai_should_reply(reason: String, context: Dictionary)

# Timing constants
const PAUSE_THRESHOLD = 4.0  # seconds
const MESSAGE_WINDOW = 10.0  # look at last 10 seconds

var last_message_time: float = 0.0
var message_queue: Array = []  # Recent messages
var ai_character_name: String = ""

func _ready():
	ai_character_name = "Obama"  # Set per AI instance

func _process(delta):
	# Check for natural pause
	var time_since_last = Time.get_unix_time_from_system() - last_message_time
	
	if time_since_last >= PAUSE_THRESHOLD and message_queue.size() > 0:
		if _should_ai_contribute():
			ai_should_reply.emit("natural_pause", _build_context())
			message_queue.clear()  # Prevent spam

func on_message_received(player_name: String, message: String):
	"""Called when any player sends a message"""
	
	last_message_time = Time.get_unix_time_from_system()
	
	# Add to message queue with timestamp
	message_queue.append({
		"player": player_name,
		"message": message,
		"time": last_message_time
	})
	
	# Trim old messages
	_trim_old_messages()
	
	# Check immediate reply conditions
	if _is_directly_addressed(message):
		ai_should_reply.emit("direct_address", _build_context())
	
	elif _is_question_to_room(message):
		ai_should_reply.emit("room_question", _build_context())
	
	elif _is_explicit_request(message):
		ai_should_reply.emit("explicit_request", _build_context())

func _is_directly_addressed(message: String) -> bool:
	"""Check if AI is directly mentioned"""
	var msg_lower = message.to_lower()
	var name_lower = ai_character_name.to_lower()
	
	# Check for name mentions
	if name_lower in msg_lower:
		return true
	
	# Check for @mentions
	if "@" + name_lower in msg_lower:
		return true
	
	# Check for "hey [name]" patterns
	var patterns = [
		"hey " + name_lower,
		"yo " + name_lower,
		name_lower + ",",
		name_lower + "?",
		name_lower + "!"
	]
	
	for pattern in patterns:
		if pattern in msg_lower:
			return true
	
	return false

func _is_question_to_room(message: String) -> bool:
	"""Check if this is a general question"""
	var indicators = ["?", "what do you", "anyone know", "thoughts?", "opinions?"]
	var msg_lower = message.to_lower()
	
	for indicator in indicators:
		if indicator in msg_lower:
			return true
	
	return false

func _is_explicit_request(message: String) -> bool:
	"""Check for explicit AI requests"""
	var keywords = ["ai", "bot", "what do you think", "your opinion"]
	var msg_lower = message.to_lower()
	
	for keyword in keywords:
		if keyword in msg_lower:
			return true
	
	return false

func _should_ai_contribute() -> bool:
	"""Decide if AI should contribute during pause"""
	
	# Don't interrupt single message
	if message_queue.size() < 2:
		return false
	
	# Check if conversation is about AI's domain
	var relevance_score = _calculate_relevance()
	
	# AI joins if relevance > 50%
	return relevance_score > 0.5

func _calculate_relevance() -> float:
	"""Calculate how relevant the conversation is to this AI"""
	# Simple keyword-based relevance (you can make this smarter)
	
	var relevant_keywords = _get_ai_keywords()
	var total_words = 0
	var relevant_words = 0
	
	for msg in message_queue:
		var words = msg["message"].split(" ")
		total_words += words.size()
		
		for word in words:
			if word.to_lower() in relevant_keywords:
				relevant_words += 1
	
	if total_words == 0:
		return 0.0
	
	return float(relevant_words) / float(total_words)

func _get_ai_keywords() -> Array:
	"""Get keywords relevant to this AI's personality"""
	# This should be defined per personality
	match ai_character_name:
		"Obama":
			return ["president", "politics", "hope", "change", "policy", "election"]
		"Peter":
			return ["chicken", "beer", "pawtucket", "family", "meg", "cartoon"]
		"Guard":
			return ["castle", "sword", "knight", "kingdom", "king", "duty"]
		_:
			return []

func _trim_old_messages():
	"""Remove messages older than window"""
	var current_time = Time.get_unix_time_from_system()
	
	message_queue = message_queue.filter(func(msg):
		return current_time - msg["time"] < MESSAGE_WINDOW
	)

func _build_context() -> Dictionary:
	"""Build context dictionary for AI prompting"""
	return {
		"recent_messages": message_queue,
		"participant_count": _get_unique_participants(),
		"conversation_topic": _detect_topic(),
		"time_since_last": Time.get_unix_time_from_system() - last_message_time
	}

func _get_unique_participants() -> int:
	var participants = {}
	for msg in message_queue:
		participants[msg["player"]] = true
	return participants.size()

func _detect_topic() -> String:
	"""Simple topic detection - can be made smarter"""
	# Count most frequent keywords
	var word_freq = {}
	
	for msg in message_queue:
		var words = msg["message"].split(" ")
		for word in words:
			var w = word.to_lower().strip_edges()
			if w.length() > 3:  # Ignore short words
				word_freq[w] = word_freq.get(w, 0) + 1
	
	# Find most common word
	var max_count = 0
	var topic = "general"
	
	for word in word_freq:
		if word_freq[word] > max_count:
			max_count = word_freq[word]
			topic = word
	
	return topic
