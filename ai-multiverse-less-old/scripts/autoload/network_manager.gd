extends Node

var peer: ENetMultiplayerPeer

# Signals
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_created()
signal server_joined()
signal connection_failed()

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_server(port: int = 9999, max_clients: int = 10):
	"""Create multiplayer server"""
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, max_clients)
	
	if error != OK:
		push_error("[NetworkManager] Failed to create server: " + str(error))
		return
	
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Server created on port ", port)
	server_created.emit()

func join_server(address: String = "127.0.0.1", port: int = 9999):
	"""Join multiplayer server"""
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		push_error("[NetworkManager] Failed to join server: " + str(error))
		connection_failed.emit()
		return
	
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Connecting to ", address, ":", port)

func _on_player_connected(peer_id: int):
	print("[NetworkManager] Player connected: ", peer_id)
	player_connected.emit(peer_id)
	
	# Server spawns player for new peer
	if multiplayer.is_server():
		var spawn_pos = Vector3(randf_range(-5, 5), 1, randf_range(-5, 5))
		GameManager.spawn_player(peer_id, spawn_pos)

func _on_player_disconnected(peer_id: int):
	print("[NetworkManager] Player disconnected: ", peer_id)
	player_disconnected.emit(peer_id)
	
	# Remove player
	if GameManager.players.has(peer_id):
		var player_node = GameManager.players[peer_id].node
		player_node.queue_free()
		GameManager.players.erase(peer_id)

func _on_connected_to_server():
	print("[NetworkManager] Successfully connected to server")
	server_joined.emit()
	GameManager.local_player_id = multiplayer.get_unique_id()

func _on_connection_failed():
	print("[NetworkManager] Connection to server failed")
	connection_failed.emit()

func _on_server_disconnected():
	print("[NetworkManager] Disconnected from server")
