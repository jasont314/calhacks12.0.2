# res://scripts/autoload/network_manager.gd
extends Node

# Signals
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

# Network settings
const PORT = 7777
const MAX_PLAYERS = 10

# Player data
var players = {}
var player_info = {"name": "Player"}

# Scenes
var player_scene = preload("res://scenes/player/player.tscn")

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_server(player_name: String):
	print("========== CREATE_SERVER CALLED ==========")
	print("Player name: ", player_name)
	
	player_info.name = player_name
	
	var peer = ENetMultiplayerPeer.new()
	print("Creating server peer...")
	var error = peer.create_server(PORT, MAX_PLAYERS)
	
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return error
	
	print("Server created successfully!")
	multiplayer.multiplayer_peer = peer
	
	print("Server created on port ", PORT)
	print("My peer ID: ", multiplayer.get_unique_id())
	
	# Add host player
	players[1] = player_info
	print("About to call _add_player(1)...")
	_add_player(1)
	print("_add_player(1) completed!")
	
	return OK

# Join a game
func join_server(address: String, player_name: String):
	player_info.name = player_name
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	
	if error != OK:
		push_error("Failed to join server: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = peer
	
	print("Connecting to ", address, ":", PORT)
	
	return OK

# Called on server when a player connects
func _on_player_connected(id: int):
	print("Player connected: ", id)
	
	# Send existing players to new player
	_register_player.rpc_id(id, player_info)

# Called on clients when they connect to server
func _on_connected_to_server():
	print("Connected to server!")
	# Send our info to server
	_register_player.rpc_id(1, player_info)

# Called when connection fails
func _on_connection_failed():
	print("Connection failed!")
	multiplayer.multiplayer_peer = null

# Called on everyone when a player disconnects
func _on_player_disconnected(id: int):
	print("Player disconnected: ", id)
	players.erase(id)
	_remove_player(id)

# Called on clients when server disconnects
func _on_server_disconnected():
	print("Server disconnected!")
	multiplayer.multiplayer_peer = null
	players.clear()
	# Remove all player nodes
	get_tree().call_group("players", "queue_free")

# RPC: Register player info
@rpc("any_peer", "reliable")
func _register_player(info: Dictionary):
	var id = multiplayer.get_remote_sender_id()
	players[id] = info
	
	# If we're the server, tell everyone about this new player
	if multiplayer.is_server():
		for peer_id in players:
			_register_player.rpc(players[peer_id])
	
	# Spawn the player
	_add_player(id)

func _add_player(id: int):
	print("========== SPAWNING PLAYER ==========")
	print("Peer ID: ", id)
	print("My peer ID: ", multiplayer.get_unique_id())
	
	var player = player_scene.instantiate()
	player.name = str(id)
	player.player_id = id
	
	# IMPORTANT: Set authority BEFORE adding to scene tree
	player.set_multiplayer_authority(id)
	print("Authority set to: ", id)
	
	# Add to scene
	var main_world = get_tree().root.get_node("MainWorld")
	main_world.add_child(player, true)  # true = force readable name
	player.add_to_group("players")
	
	# Spawn position
	player.position = Vector3(randf_range(-5, 5), 2, randf_range(-5, 5))
	
	# Wait a frame then verify
	await get_tree().process_frame
	
	print("Player spawned!")
	print("  - Name: ", player.name)
	print("  - Position: ", player.position)
	print("  - Authority: ", player.get_multiplayer_authority())
	print("  - Is authority: ", player.is_multiplayer_authority())
	print("=====================================")

# Remove a player node
func _remove_player(id: int):
	var player = get_tree().root.get_node_or_null("MainWorld/" + str(id))
	if player:
		player.queue_free()
