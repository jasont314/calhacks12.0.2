# res://scripts/autoload/game_manager.gd
extends Node

# Game state
var is_server: bool = false
var player_name: String = "Player"
var local_player_id: int = -1

# Player tracking (multiplayer)
var players: Dictionary = {}
var ai_characters: Dictionary = {}

# Signals
signal player_spawned(peer_id: int, player_node: Node)
signal player_despawned(peer_id: int)
signal ai_character_spawned(ai_id: String, ai_node: Node)

func _ready():
	print("[GameManager] Ready")

func start_as_host(port: int = 9999):
	NetworkManager.create_server(port)
	is_server = true
	print("[GameManager] Started as host on port ", port)

func join_game(address: String = "127.0.0.1", port: int = 9999):
	NetworkManager.join_server(address, port)
	is_server = false
	print("[GameManager] Joining game at ", address, ":", port)

func spawn_player(peer_id: int, spawn_position: Vector3):
	"""Spawn a player character (called on server)"""
	print("[GameManager] 🎮 Spawning player ", peer_id, " at ", spawn_position)
	
	# This must be called on the server
	if not multiplayer.is_server():
		push_error("[GameManager] spawn_player() can only be called on server!")
		return
	
	var player_scene = preload("res://scenes/player/player.tscn")
	var player = player_scene.instantiate()
	player.name = str(peer_id)  # IMPORTANT: Name must be string of peer_id
	player.position = spawn_position
	
	# SET AUTHORITY BEFORE ADDING
	player.set_multiplayer_authority(peer_id)
	print("[GameManager] Set authority ", peer_id, " for player ", player.name)
	
	# Add to Players node - MultiplayerSpawner will auto-replicate!
	var players_node = get_tree().root.get_node("MainWorld/Players")
	if players_node:
		players_node.add_child(player, true)  # true = force readable name
		print("[GameManager] ✅ Player ", peer_id, " added to scene")
	else:
		push_error("[GameManager] Players node not found!")
		return
	
	players[peer_id] = {
		"node": player,
		"name": "Player_" + str(peer_id)
	}
	
	player_spawned.emit(peer_id, player)

func spawn_ai_character(ai_id: String, personality: String, spawn_pos: Vector3):
	"""Spawn AI character (server only)"""
	if not is_server:
		return
	
	var ai_scene = preload("res://scenes/ai_characters/ai_character.tscn")
	var ai = ai_scene.instantiate()
	ai.name = ai_id
	ai.position = spawn_pos
	ai.personality_id = personality
	
	var ai_node = get_tree().root.get_node("MainWorld/AICharacters")
	if ai_node:
		ai_node.add_child(ai)
		ai_characters[ai_id] = ai
		ai_character_spawned.emit(ai_id, ai)
		print("[GameManager] Spawned AI ", ai_id)
