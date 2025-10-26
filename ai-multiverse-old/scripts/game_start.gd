# res://scripts/game_starter.gd
extends Node

func _ready():
	print("========== GAME STARTER ==========")
	
	# Auto-start server when scene loads
	NetworkManager.create_server("TestPlayer")
	
	print("Server started! Player should spawn now.")
