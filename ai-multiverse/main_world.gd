# res://scenes/main_world.gd
extends Node3D

var peer = ENetMultiplayerPeer.new()
@export var player_scene : PackedScene


func _ready() -> void:
	# Make sure the cursor is visible when the game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	

func _unhandled_input(event: InputEvent) -> void:
	# Optional: press Esc to release the mouse if it ever gets captured
	if event.is_action_pressed("mouse"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_host_pressed() -> void:
	peer.create_server(1027)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(add_player)
	add_player()
	$CanvasLayer.hide()
	
func _on_join_pressed() -> void:
	peer.create_client("127.0.0.1", 1027)
	multiplayer.multiplayer_peer = peer
	$CanvasLayer.hide()
	
func add_player(id=1):
	var player = player_scene.instantiate()
	player.name = str(id)
	call_deferred("add_child", player)
	
	player.get_node("AudioController").setupAudio(1)
	add_child(player)
	
func exit_game(id):
	multiplayer.peer_disconnected.connect(del_player)	
	del_player(id)

func del_player(id): 
	rpc("_del_player", id) 

@rpc("any_peer", "call_local")
func _del_player(id):
	get_node(str(id)).queue_free()
