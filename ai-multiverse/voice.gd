# Voice.gd
extends Node

var _udp := PacketPeerUDP.new()
var _connected := false

func connect_ctrl(port: int = 7878) -> void:
	if _connected: return
	var err := _udp.connect_to_host("127.0.0.1", port)
	if err == OK:
		_connected = true
	else:
		push_error("Voice: failed to connect to sidecar ctrl port %d (err %d)" % [port, err])

func _send(dict_msg: Dictionary) -> void:
	if not _connected: return
	var json := JSON.stringify(dict_msg) + "\n"
	_udp.put_packet(json.to_utf8_buffer())

func join(channel: String) -> void:
	_send({"cmd":"join", "channel": channel})

func leave() -> void:
	_send({"cmd":"leave"})

func ptt(state: bool) -> void:
	_send({"cmd":"ptt", "state": state})

func shutdown() -> void:
	_send({"cmd":"shutdown"})
