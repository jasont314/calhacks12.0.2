# res://scenes/main_world.gd
extends Node3D

var peer := ENetMultiplayerPeer.new()
@export var player_scene: PackedScene

# ---- Voice sidecar config (your proximity VOIP / Mumble-style) ----
const SIDECAR_RES_PATH := "res://voice-chat/sidecar/voip_sidecar.py"
const MURMUR_PORT      := 64738
const CHANNEL_NAME     := "Demo"
const CTRL_PORT        := 7878

var _sidecar_pid := -1

# ---- AI group chat / transcription system ----
var ai_server: AIChatServer
var ws_listener: WSListener

func _ready() -> void:
	# Mouse initially free
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	print("[WORLD] Ready. Voice sidecar path (res): ", SIDECAR_RES_PATH)

	# 1. Spin up AI world (Obama / Trump / SpongeBob / Peter + TTS queue)
	ai_server = AIChatServer.new()
	add_child(ai_server)
	print("[WORLD] AIChatServer added")

	# 2. Spin up the speech-to-text listener for the local player
	ws_listener = WSListener.new()
	ws_listener.local_player_name = "PlayerLocal"  # or derive from profile / username
	ws_listener.target_server = ai_server

	# OPTIONAL: if you already have a RichTextLabel in this world for subtitles/chat,
	# assign it here so transcripts appear in game:
	# ws_listener.transcript_label_path = $"CanvasLayer/TranscriptLabel"

	add_child(ws_listener)
	print("[WORLD] WSListener added as child")

	# 3. Start the listener (this creates the WebSocket server and launches transcribe.py)
	ws_listener.start_listener()
	print("[WORLD] WSListener.start_listener() called")

	# NOTE: we're not auto-starting your Mumble-style voice sidecar yet.
	# that still happens when Host/Join buttons fire.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# -------------------- UI callbacks --------------------

func _on_host_pressed() -> void:
	# 1) Start game server
	var ok := peer.create_server(1027) == OK
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(add_player)
	add_player()
	$CanvasLayer.hide()
	print("[WORLD] HOST: ENet server started on :1027 (ok=", ok, ")")

	# 2) Start voice sidecar (proximity voice thing)
	var sidecar_path := ProjectSettings.globalize_path(SIDECAR_RES_PATH)
	var server_ip := _get_lan_ip()
	var username := "Host_%s" % multiplayer.get_unique_id()
	_start_voice(sidecar_path, server_ip, username, CHANNEL_NAME)

func _on_join_pressed() -> void:
	var host_ip := "127.0.0.1"  # TODO: replace w/ UI input
	var ok := peer.create_client(host_ip, 1027) == OK
	multiplayer.multiplayer_peer = peer
	$CanvasLayer.hide()
	print("[WORLD] JOIN: Connecting to ENet host ", host_ip, ":1027 (ok=", ok, ")")

	# Start sidecar for proximity audio and control port
	var sidecar_path := ProjectSettings.globalize_path(SIDECAR_RES_PATH)
	var username := "Client_%s" % multiplayer.get_unique_id()
	_start_voice(sidecar_path, host_ip, username, CHANNEL_NAME)


# -------------------- Player mgmt --------------------

func add_player(id := 1) -> void:
	var player = player_scene.instantiate()
	player.name = str(id)
	call_deferred("add_child", player)
	print("[WORLD] add_player id=", id)

func exit_game(id: int) -> void:
	multiplayer.peer_disconnected.connect(del_player)
	del_player(id)

func del_player(id: int) -> void:
	rpc("_del_player", id)

@rpc("any_peer", "call_local")
func _del_player(id: int) -> void:
	if has_node(str(id)):
		get_node(str(id)).queue_free()
		print("[WORLD] del_player id=", id)


# -------------------- Voice sidecar helpers --------------------

func _start_voice(sidecar_path: String, server_ip: String, username: String, channel: String) -> void:
	var args = [
		"--server", server_ip,
		"--port", str(MURMUR_PORT),
		"--username", username,
		"--channel", channel,
		"--ctrl-port", str(CTRL_PORT)
	]
	_sidecar_pid = OS.create_process("python3", [sidecar_path] + args, false)
	print("[VOICE] Launching sidecar:",
		"\n        path: ", sidecar_path,
		"\n        pid : ", _sidecar_pid,
		"\n        host: ", server_ip, ":", MURMUR_PORT,
		"\n        user: ", username,
		"\n        chan: ", channel,
		"\n        ctrl: 127.0.0.1:", CTRL_PORT
	)

	Voice.connect_ctrl(CTRL_PORT)
	Voice.join(channel)

	_smoke_test_ptt()

func _smoke_test_ptt() -> void:
	print("[VOICE] Smoke test: PTT ON for 0.5s...")
	Voice.ptt(true)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(func():
		Voice.ptt(false)
		print("[VOICE] Smoke test: PTT OFF")
	)


# -------------------- Shutdown --------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		print("[WORLD] Shutting down voice…")
		Voice.shutdown()
		# If you want, you could also kill ws_listener.python_pid here
		# (Godot doesn't auto-kill children unless you handle it similarly to _exit_tree())


# -------------------- Utils --------------------

func _get_lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"
