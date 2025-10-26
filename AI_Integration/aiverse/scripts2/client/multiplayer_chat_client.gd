# res://scripts/client/multiplayer_chat_client.gd
extends Control

const SERVER_IP = "127.0.0.1"  # localhost for testing
const SERVER_PORT = 9999

var peer = ENetMultiplayerPeer.new()
var player_name: String = ""

@onready var chat_display = $ChatDisplay
@onready var message_input = $MessageInput
@onready var send_button = $SendButton

func _ready():
	player_name = "Player" + str(randi() % 1000)
	
	send_button.pressed.connect(_on_send_pressed)
	message_input.text_submitted.connect(_on_message_submitted)
	
	connect_to_server()

func connect_to_server():
	peer.create_client(SERVER_IP, SERVER_PORT)
	multiplayer.multiplayer_peer = peer
	
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	print("🔌 Connecting to server...")

func _on_connected():
	print("✅ Connected to server!")
	
	# Register with server
	rpc_id(1, "register_player", player_name)

func _on_connection_failed():
	print("❌ Connection failed")

func _on_send_pressed():
	_send_message()

func _on_message_submitted(text: String):
	_send_message()

func _send_message():
	var msg = message_input.text.strip_edges()
	if msg.is_empty():
		return
	
	# Send to server
	rpc_id(1, "send_chat_message", msg)
	
	message_input.text = ""

@rpc("authority", "call_remote")
func receive_message(sender_name: String, message: String):
	"""Receive a message from server"""
	var formatted = "[%s]: %s\n" % [sender_name, message]
	chat_display.text += formatted
	
	# Auto-scroll to bottom
	chat_display.scroll_vertical = INF

@rpc("authority", "call_remote")
func receive_history(history: Array):
	"""Receive chat history when joining"""
	chat_display.text = "=== Chat History ===\n"
	
	for msg in history:
		var name = msg.get("name", "Unknown")
		var content = msg.get("content", "")
		chat_display.text += "[%s]: %s\n" % [name, content]

@rpc("authority", "call_remote")
func player_left(player_name: String):
	"""Someone left"""
	chat_display.text += "--- %s left the chat ---\n" % player_name

@rpc("authority", "call_remote")
func ai_typing(is_typing: bool):
	"""AI is typing indicator"""
	if is_typing:
		chat_display.text += "💭 AI is thinking...\n"
	else:
		# Remove typing indicator (you'd implement this better)
		pass
