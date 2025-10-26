# res://scripts/autoload/voice_manager.gd
# STUB FOR PERSON 3 TO IMPLEMENT

extends Node

# Signals for Person 3 to implement
signal voice_started(peer_id: int)
signal voice_stopped(peer_id: int)
signal audio_received(peer_id: int, audio_data: PackedByteArray)

var is_push_to_talk: bool = true
var is_muted: bool = false

func _ready():
	print("[VoiceManager] Ready (stub - Person 3 will implement)")

# Person 3 will implement these:
func start_recording():
	print("[VoiceManager] TODO: Start recording audio")

func stop_recording():
	print("[VoiceManager] TODO: Stop recording audio")

func set_output_volume(volume_db: float):
	print("[VoiceManager] TODO: Set output volume to ", volume_db)

func mute_player(peer_id: int, muted: bool):
	print("[VoiceManager] TODO: Mute/unmute player ", peer_id)
