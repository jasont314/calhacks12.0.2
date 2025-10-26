extends Node

signal player_joined(id)
signal player_left(id)
signal new_transcription(player_id, text, timestamp)

# --- Core data ---
var players = {}            # player_id -> Player ref
var muted = {}              # player_id -> bool
var conversation_log = []   # [ {timestamp, player_id, text}, ... ]

# --- References ---
var server = null            # Assigned externally (Server.gd instance)
var fish_audio = null        # Assigned externally (FishAudio.gd instance)

# --- Audio ---
var audio_streams = {}       # player_id -> AudioStreamPlayer
var mic = null
var recording = false

func _ready():
    print("VoiceChat system ready")

# --- Connect a player ---
func add_player(player_id, player_ref):
    players[player_id] = player_ref
    muted[player_id] = false
    var stream = AudioStreamPlayer.new()
    add_child(stream)
    audio_streams[player_id] = stream
    emit_signal("player_joined", player_id)
    print("Player %s joined voice chat" % player_id)

# --- Remove a player ---
func remove_player(player_id):
    if players.has(player_id):
        players.erase(player_id)
        muted.erase(player_id)
        audio_streams[player_id].queue_free()
        audio_streams.erase(player_id)
        emit_signal("player_left", player_id)
        print("Player %s left voice chat" % player_id)

# --- Toggle mute ---
func toggle_mute(player_id):
    muted[player_id] = !muted[player_id]
    print("Player %s mute: %s" % [player_id, muted[player_id]])

# --- Begin recording (local mic) ---
func start_recording():
    if recording:
        return
    mic = AudioEffectRecord.new()
    AudioServer.add_bus_effect(0, mic)
    mic.set_recording_active(true)
    recording = true
    print("🎙️ Recording started")

# --- Stop recording and process ---
func stop_recording(player_id):
    if not recording:
        return
    recording = false
    var audio = mic.get_recording()
    mic.set_recording_active(false)
    AudioServer.remove_bus_effect(0, mic)
    mic = null

    _broadcast_audio(player_id, audio)

    # Transcribe locally (stub)
    var text = _transcribe_audio(audio)
    var timestamp = Time.get_datetime_string_from_system()
    conversation_log.append({
        "timestamp": timestamp,
        "player_id": player_id,
        "text": text
    })
    emit_signal("new_transcription", player_id, text, timestamp)

    # Send to local server
    if server:
        var ai_response = server.process_message(player_id, text, timestamp, conversation_log)
        if ai_response:
            _handle_ai_response(ai_response)

# --- Broadcast to others ---
func _broadcast_audio(sender_id, audio):
    for id in players.keys():
        if id == sender_id or muted.get(id, false):
            continue
        audio_streams[id].stream = audio
        audio_streams[id].play()

# --- Dummy transcription ---
func _transcribe_audio(audio_data) -> String:
    # This is just a stub — replace with real speech-to-text if needed
    return "sample transcription from player"

# --- Handle AI reply (from local server) ---
func _handle_ai_response(response: Dictionary):
    var ai_text = response.get("ai_text", "")
    var ai_voice = response.get("voice_model", "")

    if fish_audio:
        var audio_stream = fish_audio.synthesize(ai_text, ai_voice)
        if audio_stream:
            var ai_player = AudioStreamPlayer.new()
            add_child(ai_player)
            ai_player.stream = audio_stream
            ai_player.play()
            print("🔊 AI Voice Played: %s" % ai_text)
    else:
        print("🤖 AI (text only): %s" % ai_text)
