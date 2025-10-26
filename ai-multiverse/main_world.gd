# res://scenes/main_world.gd
extends Node3D

var peer := ENetMultiplayerPeer.new()
@export var player_scene: PackedScene

# ---- Voice sidecar config ----
const SIDECAR_RES_PATH := "res://voice-chat/sidecar/voip_sidecar.py"
const MURMUR_PORT      := 64738
const CHANNEL_NAME     := "Demo"
const CTRL_PORT        := 7878

var _sidecar_pid := -1

func _ready() -> void:
	# Start with mouse visible in menus
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("[WORLD] Ready. Voice sidecar path (res): ", SIDECAR_RES_PATH)

func _unhandled_input(event: InputEvent) -> void:
	# Press Esc (ui_cancel) to release the mouse if it gets captured
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

	# 2) Start voice sidecar (server_ip = this machine's LAN IP)
	var sidecar_path := ProjectSettings.globalize_path(SIDECAR_RES_PATH)
	var server_ip := _get_lan_ip()
	var username := "Host_%s" % multiplayer.get_unique_id()
	_start_voice(sidecar_path, server_ip, username, CHANNEL_NAME)

func _on_join_pressed() -> void:
	# ⚠️ Replace this with the HOST’s actual LAN IP (e.g., 192.168.x.x).
	# Best: pipe a LineEdit into this var.
	var host_ip := "192.168.1.23"  # TODO: read from UI
	var ok := peer.create_client(host_ip, 1027) == OK
	multiplayer.multiplayer_peer = peer
	$CanvasLayer.hide()
	print("[WORLD] JOIN: Connecting to ENet host ", host_ip, ":1027 (ok=", ok, ")")

	# Start voice sidecar pointing to SAME host IP
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
	# Launch the Python sidecar
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

	# Connect to control port and join channel
	Voice.connect_ctrl(CTRL_PORT)
	Voice.join(channel)

	# Optional smoke-test: briefly toggle PTT so you see control packets in the sidecar logs
	_smoke_test_ptt()

func _smoke_test_ptt() -> void:
	# Sends PTT on for ~0.5s then off. Purely for visibility during setup.
	print("[VOICE] Smoke test: PTT ON for 0.5s...")
	Voice.ptt(true)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(func():
		Voice.ptt(false)
		print("[VOICE] Smoke test: PTT OFF")
	)

# Clean shutdown when window closes / node is being freed
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		print("[WORLD] Shutting down voice…")
		Voice.shutdown()
		# If you really want to kill the process, you can do it externally;
		# Godot doesn't provide a cross-platform OS.kill here.

# -------------------- Utils --------------------

func _get_lan_ip() -> String:
	# Return the first private IPv4 we find
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"  # fallback (localhost testing only)
