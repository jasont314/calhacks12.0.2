# WSListener.gd
extends Node

@export var port := 8765
@onready var label: RichTextLabel = $Label

var server := WebSocketMultiplayerPeer.new()
var full_transcript := ""

func _ready():
	var err := server.create_server(port)
	if err != OK:
		push_error("❌ WebSocket server failed to start: %s" % err)
		return
	print("✅ Listening for Python WebSocket on port %d" % port)
	set_process(true)

func _process(_delta):
	# poll incoming messages
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
