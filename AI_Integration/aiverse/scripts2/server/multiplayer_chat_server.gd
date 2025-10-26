# res://scripts/server/multiplayer_chat_server.gd
extends Node

const PORT = 9999
const MAX_PLAYERS = 20

var peer = ENetMultiplayerPeer.new()
var players: Dictionary = {}  # {player_id: {name, connected_at}}

# AI state
var reply_detector: Node
var conversation_manager: Node
var ai_thinking: bool = false

func _ready():
	start_server()
	
	# Initialize AI systems
	conversation_manager = preload("res://scripts/ai/group_conversation_manager.gd").new()
	conversation_manager.initialize("obama")  # Default personality
	add_child(conversation_manager)
	
	reply_detector = preload("res://scripts/ai/reply_detector.gd").new()
	reply_detector.ai_character_name = "Obama"
	reply_detector.ai_should_reply.connect(_on_ai_should_reply)
	add_child(reply_detector)

func start_server():
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	print("🌐 Server started on port %d" % PORT)

func _on_peer_connected(id: int):
	print("✅ Player %d connected" % id)

func _on_peer_disconnected(id: int):
	if players.has(id):
		var player_name = players[id]["name"]
		print("❌ %s disconnected" % player_name)
		players.erase(id)
		
		# Broadcast to others
		rpc("player_left", player_name)

@rpc("any_peer", "call_remote")
func register_player(player_name: String):
	"""Player sends their name when joining"""
	var sender_id = multiplayer.get_remote_sender_id()
	
	players[sender_id] = {
		"name": player_name,
		"connected_at": Time.get_unix_time_from_system()
	}
	
	print("📝 Registered player: %s (ID: %d)" % [player_name, sender_id])
	
	# Send them the chat history
	var history = conversation_manager.get_recent_messages(20)
	rpc_id(sender_id, "receive_history", history)
	
	# Announce to everyone
	var join_msg = "%s joined the chat!" % player_name
	rpc("receive_message", "System", join_msg)

@rpc("any_peer", "call_remote")
func send_chat_message(message: String):
	"""Player sends a chat message"""
	var sender_id = multiplayer.get_remote_sender_id()
	
	if not players.has(sender_id):
		push_error("Message from unregistered player: %d" % sender_id)
		return
	
	var player_name = players[sender_id]["name"]
	
	# Add to conversation manager
	conversation_manager.add_message(sender_id, player_name, message)
	
	# Broadcast to all players
	rpc("receive_message", player_name, message)
	
	# Check if AI should reply
	reply_detector.on_message_received(player_name, message)

func _on_ai_should_reply(reason: String, context: Dictionary):
	"""AI decides it should reply"""
	
	if ai_thinking:
		print("⏳ AI already thinking, skipping...")
		return
	
	ai_thinking = true
	
	# Show "AI is typing..." to everyone
	rpc("ai_typing", true)
	
	print("🤖 AI replying (reason: %s)" % reason)
	
	# Get context and generate response
	var prompt_context = conversation_manager.get_context_for_ai(reason, context)
	
	var response = await JLLMAPI.send_message(
		prompt_context["system"],
		prompt_context["messages"],
		150  # Max tokens
	)
	
	# Add AI response to history
	conversation_manager.add_ai_message(response)
	
	# Broadcast AI message
	rpc("receive_message", conversation_manager.ai_personality["name"], response)
	rpc("ai_typing", false)
	
	ai_thinking = false

# RPCs for clients (these run on client side)
@rpc("authority", "call_remote")
func receive_message(sender_name: String, message: String):
	# Implemented on client
	pass

@rpc("authority", "call_remote")
func receive_history(history: Array):
	# Implemented on client
	pass

@rpc("authority", "call_remote")
func player_left(player_name: String):
	# Implemented on client
	pass

@rpc("authority", "call_remote")
func ai_typing(is_typing: bool):
	# Implemented on client
	pass
