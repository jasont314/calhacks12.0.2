extends Node

@export var port := 8765
@export var python_path := "python3"  # or "/usr/local/bin/python3" if needed
@export var transcriber_script := "/Users/rexouyang/Desktop/calhacks/calhacks12.0.2/Voice-Integration/mic_to_godot.py"
@onready var label: RichTextLabel = $Label

var server := WebSocketMultiplayerPeer.new()
var full_transcript := ""
var python_pid := 0

func _ready():
	# 1️⃣ Start WebSocket listener
	var err := server.create_server(port)
	if err != OK:
		push_error("❌ WebSocket server failed to start: %s" % err)
		return
	print("✅ Listening for Python WebSocket on port %d" % port)
	set_process(true)

	# 2️⃣ Immediately launch Python transcriber
	print("🚀 Launching Python transcriber:", transcriber_script)
	python_pid = OS.create_process(python_path, [transcriber_script], false)
	if python_pid <= 0:
		push_error("❌ Could not start Python script. Check path or permissions.")
	else:
		print("✅ Python transcriber started (PID %d)" % python_pid)

func _process(_delta):
	server.poll()
	while server.get_available_packet_count() > 0:
		var msg_bytes := server.get_packet()
		var msg := msg_bytes.get_string_from_utf8()
		_handle_message(msg)

func _handle_message(msg: String):
	print("🎤 Transcript chunk:", msg)
	full_transcript += msg.strip_edges() + " "
	if label:
		label.text = full_transcript
		label.scroll_to_line(label.get_line_count() - 1)

# 3️⃣ Stop the Python process when you exit the scene (so it doesn’t keep running)
func _exit_tree():
	if python_pid > 0:
		print("🛑 Stopping Python process (PID %d)" % python_pid)
		OS.kill(python_pid)
