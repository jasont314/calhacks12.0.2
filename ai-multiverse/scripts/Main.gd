extends Node
class_name Main

var ai_server: AIChatServer
var ws_listener: WSListener

func _ready() -> void:
	print("[Main] _ready() starting...")

	#
	# 1. Spin up AI world (Obama / Trump / SpongeBob / Peter + TTS queue)
	#
	ai_server = AIChatServer.new()
	add_child(ai_server)
	print("[Main] AIChatServer added")

	#
	# 2. Create mic/WebSocket listener (speech -> text -> bots)
	#
	ws_listener = WSListener.new()
	print("[Main] WSListener instance created")

	# Wire it BEFORE starting
	ws_listener.local_player_name = "PlayerLocal"
	ws_listener.target_server = ai_server
	# If you have an on-screen transcript label you want to update, set it here:
	# ws_listener.transcript_label_path = $"CanvasLayer/TranscriptLabel"

	add_child(ws_listener)
	print("[Main] WSListener added as child")

	#
	# 3. NOW actually start it
	#
	ws_listener.start_listener()
	print("[Main] Called ws_listener.start_listener()")
