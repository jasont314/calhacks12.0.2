# res://scripts/ai/ai_character.gd
extends CharacterBody3D

@export var ai_name: String = "AI Character"
@export var personality_id: String = "guard"

@onready var proximity_area = $ProximityArea
@onready var name_label = $NameLabel3D
@onready var audio_player = $AudioStreamPlayer3D  # For AI voice responses

# Conversation state
var players_in_range: Array = []  # Players who can talk to this AI
var is_speaking: bool = false
var current_speaker_id: int = -1  # Who's currently talking to this AI

func _ready():
	name_label.text = ai_name
	
	# Connect proximity detection
	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)
	
	# Only server controls AI logic
	if not multiplayer.is_server():
		set_physics_process(false)

func _on_body_entered(body):
    """Player entered conversation range"""
	if body.is_in_group("players"):
		var peer_id = body.get_multiplayer_authority()
		if not players_in_range.has(peer_id):
			players_in_range.append(peer_id)
			notify_player_in_range.rpc_id(peer_id, true, ai_name, personality_id)
			print("[AI] Player ", peer_id, " entered range of ", ai_name)

func _on_body_exited(body):
    """Player left conversation range"""
	if body.is_in_group("players"):
		var peer_id = body.get_multiplayer_authority()
		if players_in_range.has(peer_id):
			players_in_range.erase(peer_id)
			notify_player_in_range.rpc_id(peer_id, false, ai_name, personality_id)
			print("[AI] Player ", peer_id, " left range of ", ai_name)

@rpc("authority", "call_remote")
func notify_player_in_range(in_range: bool, ai_name_param: String, personality: String):
    """Client is notified they can/can't talk to this AI"""
	if in_range:
		print("[AI] You can now talk to ", ai_name_param)
		# Person 3's UI shows: "Press V to talk to [ai_name]"
	else:
		print("[AI] Out of range from ", ai_name_param)
		# Person 3's UI hides the prompt

@rpc("any_peer", "call_remote")
func receive_voice_message(player_id: int, transcribed_text: String):
    """
    Server receives transcribed voice message from player.
    Called by Person 3's VoiceManager after speech-to-text.
    """
	if not multiplayer.is_server():
		return
	
	if is_speaking:
		# AI is already speaking, ignore
		return
	
	print("[AI] ", ai_name, " received message from ", player_id, ": ", transcribed_text)
	
	# Mark as speaking (prevents interrupt)
	is_speaking = true
	current_speaker_id = player_id
	
	# Person 2's system handles this:
	# 1. Send transcribed_text to Claude API
	# 2. Get text response
	# 3. Send to TTS (Fish Audio)
	# 4. Call play_ai_response() with audio data
	
	# Signal Person 2's ConversationManager
	GameManager.emit_signal("ai_received_message", name, personality_id, player_id, transcribed_text)

@rpc("authority", "call_remote")
func play_ai_response(audio_stream: AudioStream, duration: float):
    """
    Play AI's voice response (called by server after TTS).
    All clients in range hear this.
    """
	if audio_player:
		audio_player.stream = audio_stream
		audio_player.play()
		
		# Show speaking indicator (Person 3's UI)
		show_speaking_indicator.rpc(true)
		
		# Wait for audio to finish
		await get_tree().create_timer(duration).timeout
		
		# Hide speaking indicator
		show_speaking_indicator.rpc(false)
		is_speaking = false
		current_speaker_id = -1

@rpc("authority", "call_remote")
func show_speaking_indicator(speaking: bool):
    """Visual indicator that AI is speaking"""
	# Person 3 will implement UI for this
	# Could be: speech bubble, animated mouth, glowing effect
	if speaking:
		name_label.modulate = Color.YELLOW  # Simple indicator
	else:
		name_label.modulate = Color.WHITE
