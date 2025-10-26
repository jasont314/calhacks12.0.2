extends Node
class_name WSListener

@export var port := 8765
@export var python_path := "/usr/local/bin/python3"
@export var transcriber_script := "./scripts/transcribe.py"

@export var local_player_name := "PlayerLocal"
var target_server: AIChatServer = null

@export var transcript_label_path: NodePath
var transcript_label: RichTextLabel = null

var server := WebSocketMultiplayerPeer.new()
var full_transcript := ""
var python_pid := 0
var _started := false

func _ready() -> void:
	print("[WSListener] _ready() called (not starting yet)")
	# We DO NOT start the mic here.
	# Main will call start_listener() after wiring target_server/local_player_name.


func start_listener() -> void:
	if _started:
		print("[WSListener] start_listener() called again, ignoring")
		return
	_started = true

	print("[WSListener] start_listener() booting network + python")

	# optional UI label hookup
	if transcript_label_path != NodePath(""):
		var n = get_node_or_null(transcript_label_path)
		if n and n is RichTextLabel:
			transcript_label = n

	# 1) Start WebSocket server
	var err := server.create_server(port)
	if err != OK:
		push_error("❌ WSListener: WebSocket server failed on %d: %s" % [port, err])
		return
	print("✅ WSListener: Listening for Python WebSocket on port %d" % port)

	set_process(true)

	# 2) Launch python mic process
	print("🚀 WSListener: Launching Python transcriber:", transcriber_script)
	python_pid = OS.create_process(python_path, [transcriber_script], false)
	if python_pid <= 0:
		push_error("❌ WSListener: Could not start Python script. Check path or permissions.")
	else:
		print("✅ WSListener: Python transcriber started (PID %d)" % python_pid)


func _process(_delta: float) -> void:
	if !_started:
		return

	server.poll()

	while server.get_available_packet_count() > 0:
		var msg_bytes := server.get_packet()
		var msg := msg_bytes.get_string_from_utf8()
		_handle_message(msg)


func _handle_message(msg: String) -> void:
	var clean := msg.strip_edges()
	if clean == "":
		return

	print("🎤 WSListener transcript (%s): %s" % [local_player_name, clean])

	full_transcript += clean + " "
	if transcript_label:
		transcript_label.text = full_transcript
		transcript_label.scroll_to_line(transcript_label.get_line_count() - 1)

	if target_server:
		target_server.receive_player_message(local_player_name, clean)
	else:
		print("⚠ WSListener: no target_server connected yet, not forwarding to bots")


func _exit_tree() -> void:
	if python_pid > 0:
		print("🛑 WSListener: Stopping Python process (PID %d)" % python_pid)
		OS.kill(python_pid)
