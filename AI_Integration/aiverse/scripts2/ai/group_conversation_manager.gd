# res://scripts/ai/group_conversation_manager.gd
extends Node

const MAX_CONTEXT_MESSAGES = 40  # Last 40 messages
const CONTEXT_LENGTH = 25000  # JLLM limit

var group_history: Array = []  # [{player, message, timestamp}]
var ai_personality: Dictionary
var active_players: Dictionary = {}  # {player_id: {name, last_active}}

func _ready():
	pass

func initialize(personality_id: String):
	"""Initialize with a personality"""
	ai_personality = PersonalityManager.get_personality(personality_id)
	print("💬 Group chat initialized with %s" % ai_personality["name"])

func add_message(player_id: int, player_name: String, message: String):
	"""Add a player message to group history"""
	
	var timestamp = Time.get_unix_time_from_system()
	
	# Update player tracking
	active_players[player_id] = {
		"name": player_name,
		"last_active": timestamp
	}
	
	# Add to history
	group_history.append({
		"role": "user",
		"name": player_name,  # Important: track WHO said it
		"content": message,
		"timestamp": timestamp
	})
	
	# Trim if too long
	_trim_history()
	
	print("💬 %s: %s" % [player_name, message])

func add_ai_message(message: String):
	"""Add AI response to history"""
	
	group_history.append({
		"role": "assistant",
		"name": ai_personality["name"],
		"content": message,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	_trim_history()

func get_context_for_ai(trigger_reason: String, extra_context: Dictionary = {}) -> Dictionary:
	"""
    Build the prompt context for JLLM API.
    This is the CRITICAL function.
	"""
	
	# Build system prompt
	var system_prompt = _build_group_system_prompt(trigger_reason, extra_context)
	
	# Build message history in JLLM format
	var messages = _format_history_for_api()
	
	return {
		"system": system_prompt,
		"messages": messages
	}

func _build_group_system_prompt(trigger_reason: String, context: Dictionary) -> String:
	"""
    Build a sophisticated system prompt for group chat.
    This is WHERE THE MAGIC HAPPENS.
	"""
	
	var player_list = _get_player_names()
	var participant_count = active_players.size()
	var conversation_topic = context.get("conversation_topic", "general")
	
	var prompt = """You are {name}, participating in a group chat room with {count} other people: {players}.

PERSONALITY:
{personality}

CURRENT SITUATION:
- You were triggered to reply because: {reason}
- Current topic: {topic}
- Participants in this conversation: {participants}

GROUP CHAT RULES:
1. Address people by name when replying to them specifically
2. Keep responses SHORT (1-3 sentences max) - this is a fast-paced chat
3. Don't monopolize the conversation - let others talk
4. If multiple people are talking, you can address multiple people
5. Use natural chat language (casual, quick responses)
6. React to what people are saying, don't just monologue
7. If someone asks you directly, prioritize answering them
8. You can ignore messages not relevant to you - don't feel obligated to respond to everything
9. Stay in character but be conversational

RESPONSE STYLE:
- Short and punchy (like texting)
- Natural reactions ("lol", "wait what?", "oh man")
- Address specific people when relevant
- Don't be too formal unless it's your character

Remember: This is a GROUP chat. Multiple conversations can happen at once. Be aware of the social dynamics.
""".format({
		"name": ai_personality["name"],
		"count": participant_count,
		"players": ", ".join(player_list),
		"personality": ai_personality["system_prompt"],
		"reason": trigger_reason,
		"topic": conversation_topic,
		"participants": participant_count + 1
	})
	
	return prompt

func _format_history_for_api() -> Array:
	"""
    Format group history for JLLM API.
    Key insight: Include WHO said each message.
	"""
	
	var formatted = []
	
	for msg in group_history:
		var role = msg["role"]
		var name = msg["name"]
		var content = msg["content"]
		
		if role == "user":
			# Format: "[PlayerName]: message"
			formatted.append({
				"role": "user",
				"content": "[%s]: %s" % [name, content]
			})
		else:
			# AI messages
			formatted.append({
				"role": "assistant",
				"content": content
			})
	
	return formatted

func _trim_history():
	"""Keep history manageable"""
	
	# Method 1: Simple count-based trimming
	if group_history.size() > MAX_CONTEXT_MESSAGES:
		group_history = group_history.slice(-MAX_CONTEXT_MESSAGES)
	
	# Method 2: Token-based trimming (more accurate)
	var estimated_tokens = _estimate_token_count()
	
	while estimated_tokens > CONTEXT_LENGTH * 0.8:  # Leave 20% buffer
		# Remove oldest messages
		if group_history.size() <= 5:  # Keep minimum context
			break
		
		group_history.pop_front()
		estimated_tokens = _estimate_token_count()

func _estimate_token_count() -> int:
	"""Rough token estimation (1 token ≈ 4 characters)"""
	var total_chars = 0
	
	for msg in group_history:
		total_chars += msg["content"].length()
	
	return total_chars / 4

func _get_player_names() -> Array:
	var names = []
	for player_id in active_players:
		names.append(active_players[player_id]["name"])
	return names

func get_recent_messages(count: int = 10) -> Array:
	"""Get last N messages for display"""
	if group_history.size() <= count:
		return group_history.duplicate()
	
	return group_history.slice(-count)

func clear_inactive_players():
	"""Remove players who haven't spoken in 5 minutes"""
	var current_time = Time.get_unix_time_from_system()
	var timeout = 300.0  # 5 minutes
	
	for player_id in active_players.keys():
		var player = active_players[player_id]
		if current_time - player["last_active"] > timeout:
			print("🚪 %s left due to inactivity" % player["name"])
			active_players.erase(player_id)
