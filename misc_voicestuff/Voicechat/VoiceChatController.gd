# VoiceChatController.gd
# Attach this to the root node of VoiceChatController.tscn

extends Node

#
# ========== CONFIG ==========
#

const CHUNK_DURATION_SEC := 2.0        # duration per audio capture chunk
const SAMPLE_RATE := 44100             # sample rate in Hz
const CHANNELS := 1                    # mono
const SILENCE_THRESHOLD := 0.01        # ignore very quiet chunks

const FISH_ASR_URL := "https://api.fish.audio/v1/asr"
const FISH_TTS_URL := "https://api.fish.audio/v1/tts"

# Chat server is now local
const SERVER_SCRIPT_PATH := "res://Server.gd"

#
# ========== NODES ==========
#

@onready var mute_button: Button = $MuteButton
@onready var status_label: Label = $StatusLabel

var tts_player: AudioStreamPlayer

#
# ========== STATE ==========
#

var FISH_API_KEY := ""                 # will be provided at runtime via command line
var is_muted := false
var time_accum := 0.0
var capture_bus_idx := -1

# transcription & chat state
var last_user_text := ""
var last_ai_text := ""
var full_transcript := ""
var conversation_log: Array = []       # [{timestamp, text}, ...]
var transcribe_running := false

# Local server instance
var server = null

#
# ========== SIGNALS ==========
#

signal transcript_updated(new_chunk: String, full_text: String)
signal ai_replied(user_text: String, ai_text: String)

#
# ========== READY ==========
#

func _ready() -> void:
    _load_api_key_from_cmd()
    if FISH_API_KEY == "":
        push_error("❌ Missing Fish Audio API key. Run with: godot --path . --fish_api_key YOUR_KEY")
        status_label.text = "Missing API key!"
        return

    # Initialize local server
    server = preload(SERVER_SCRIPT_PATH).new()

    # Hook mute button
    mute_button.pressed.connect(_on_mute_button_pressed)

    # Create audio player for TTS output
    tts_player = AudioStreamPlayer.new()
    add_child(tts_player)

    # Find capture bus
    capture_bus_idx = AudioServer.get_bus_index("CaptureBus")
    if capture_bus_idx == -1:
        push_warning("No 'CaptureBus' found. Please create it and add AudioEffectCapture.")
    else:
        AudioServer.set_bus_recording_active(capture_bus_idx, true)

    status_label.text = "Ready (unmuted)"
    print("🎧 VoiceChatController ready, API key loaded")

    # Start continuous transcription
    transcribe_audio()


#
# ========== LOAD API KEY ==========
#

func _load_api_key_from_cmd():
    var args = OS.get_cmdline_args()
    for i in range(args.size()):
        if args[i] == "--fish_api_key" and i + 1 < args.size():
            FISH_API_KEY = args[i + 1]
            break
    if FISH_API_KEY == "":
        FISH_API_KEY = ProjectSettings.get_setting("fish_audio/default_api_key", "")


#
# ========== MUTE / UNMUTE ==========
#

func _on_mute_button_pressed() -> void:
    is_muted = !is_muted
    mute_button.text = is_muted ? "Unmute" : "Mute"
    status_label.text = is_muted ? "Muted." : "Listening..."
    if not is_muted and not transcribe_running:
        transcribe_audio()
    elif is_muted:
        stop_transcribe_audio()


#
# ========== CONTINUOUS TRANSCRIPTION ==========
#

@func
async func transcribe_audio():
    if transcribe_running:
        push_warning("Transcription already running")
        return
    transcribe_running = true
    print("🎙️ Continuous transcription started")

    while transcribe_running:
        await get_tree().create_timer(CHUNK_DURATION_SEC).timeout

        if is_muted:
            continue

        var chunk := _pull_audio_chunk()
        if chunk.is_empty() or _is_silent(chunk):
            continue

        var user_text := await _transcribe_chunk(chunk)
        if user_text == null or user_text.strip_edges() == "":
            continue

        # Timestamp
        var timestamp := Time.get_datetime_string_from_system()

        # Append to logs
        conversation_log.append({
            "timestamp": timestamp,
            "text": user_text
        })

        if full_transcript == "":
            full_transcript = user_text
        else:
            full_transcript += " " + user_text

        last_user_text = user_text
        emit_signal("transcript_updated", user_text, full_transcript)
        status_label.text = "🗣️ " + full_transcript

        # Send to AI via local server
        var ai_text := await _get_ai_reply(user_text)
        if ai_text != "":
            last_ai_text = ai_text
            emit_signal("ai_replied", user_text, ai_text)
            conversation_log.append({
                "timestamp": Time.get_datetime_string_from_system(),
                "ai_text": ai_text
            })
            var wav_bytes := await _tts_generate(ai_text)
            var stream := _wav_bytes_to_stream(wav_bytes)
            if stream:
                tts_player.stream = stream
                tts_player.play()
                print("🔊 AI replied: ", ai_text)

    print("🛑 Continuous transcription stopped")


func stop_transcribe_audio():
    transcribe_running = false


#
# ========== AUDIO CAPTURE ==========
#

func _pull_audio_chunk() -> PackedFloat32Array:
    if capture_bus_idx == -1:
        return PackedFloat32Array()
    if AudioServer.get_bus_effect_count(capture_bus_idx) == 0:
        return PackedFloat32Array()

    var cap_effect := AudioServer.get_bus_effect(capture_bus_idx, 0)
    if cap_effect == null:
        return PackedFloat32Array()

    var frames_available = cap_effect.get_frames_available()
    if frames_available <= 0:
        return PackedFloat32Array()

    var frames_to_read = int(CHUNK_DURATION_SEC * SAMPLE_RATE)
    frames_to_read = min(frames_to_read, frames_available)
    var buffer = cap_effect.get_buffer(frames_to_read)

    var mono := PackedFloat32Array()
    if typeof(buffer) == TYPE_PACKED_VECTOR2_ARRAY:
        mono.resize(buffer.size())
        for i in range(buffer.size()):
            mono[i] = (buffer[i].x + buffer[i].y) * 0.5
    elif typeof(buffer) == TYPE_PACKED_FLOAT32_ARRAY:
        mono = buffer
    return mono


func _is_silent(samples: PackedFloat32Array) -> bool:
    var max_mag := 0.0
    for s in samples:
        var a = absf(s)
        if a > max_mag:
            max_mag = a
    return max_mag < SILENCE_THRESHOLD


#
# ========== WAV ENCODING ==========
#

func _encode_wav_bytes_from_float(samples: PackedFloat32Array, sample_rate: int) -> PackedByteArray:
    var pcm16 := PackedByteArray()
    pcm16.resize(samples.size() * 2)
    for i in range(samples.size()):
        var v = clamp(samples[i], -1.0, 1.0)
        var iv = int(round(v * 32767.0))
        pcm16[i * 2] = iv & 0xFF
        pcm16[i * 2 + 1] = (iv >> 8) & 0xFF

    var num_channels = 1
    var bits_per_sample = 16
    var byte_rate = sample_rate * num_channels * bits_per_sample / 8
    var block_align = num_channels * bits_per_sample / 8
    var subchunk2_size = pcm16.size()
    var chunk_size = 36 + subchunk2_size

    var header = PackedByteArray()
    header.append_array("RIFF".to_utf8_buffer())
    header.append_array(_le32(chunk_size))
    header.append_array("WAVE".to_utf8_buffer())
    header.append_array("fmt ".to_utf8_buffer())
    header.append_array(_le32(16))
    header.append_array(_le16(1))
    header.append_array(_le16(num_channels))
    header.append_array(_le32(sample_rate))
    header.append_array(_le32(byte_rate))
    header.append_array(_le16(block_align))
    header.append_array(_le16(bits_per_sample))
    header.append_array("data".to_utf8_buffer())
    header.append_array(_le32(subchunk2_size))

    var wav_bytes = PackedByteArray()
    wav_bytes.append_array(header)
    wav_bytes.append_array(pcm16)
    return wav_bytes


func _le16(v: int) -> PackedByteArray:
    var b := PackedByteArray()
    b.resize(2)
    b[0] = v & 0xFF
    b[1] = (v >> 8) & 0xFF
    return b

func _le32(v: int) -> PackedByteArray:
    var b := PackedByteArray()
    b.resize(4)
    b[0] = v & 0xFF
    b[1] = (v >> 8) & 0xFF
    b[2] = (v >> 16) & 0xFF
    b[3] = (v >> 24) & 0xFF
    return b


#
# ========== FISHAUDIO ASR ==========
#

func _transcribe_chunk(samples: PackedFloat32Array) -> Signal:
    return _async_transcribe(samples)

@func
async func _async_transcribe(samples: PackedFloat32Array) -> String:
	var wav_bytes := _encode_wav_bytes_from_float(samples, SAMPLE_RATE)
	var boundary := "----------------GodotFishBoundary123"
	var body := PackedByteArray()

	func append_text(s: String) -> void:
		body.append_array(s.to_utf8_buffer())

	# Build multipart body as real binary
	append_text("--%s\r\n" % boundary)
	append_text("Content-Disposition: form-data; name=\"audio\"; filename=\"chunk.wav\"\r\n")
	append_text("Content-Type: audio/wav\r\n\r\n")
	body.append_array(wav_bytes)
	append_text("\r\n--%s--\r\n" % boundary)

	var headers = [
		"Authorization: Bearer " + FISH_API_KEY,
		"Content-Type: multipart/form-data; boundary=" + boundary
	]

	var http := HTTPRequest.new()
	add_child(http)

	# IMPORTANT: use request_raw for binary
	var err := http.request_raw(FISH_ASR_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("ASR request failed: %s" % str(err))
		return ""

	var result = await http.request_completed
	http.queue_free()

	var code := result[1]
	var response_body: PackedByteArray = result[3]

	if code != 200:
		push_warning("⚠️ ASR HTTP code: %d" % code)
		print(response_body.get_string_from_utf8())
		return ""

	var raw := body.get_string_from_utf8()
    var json := JSON.parse_string(raw)
    if typeof(json) == TYPE_DICTIONARY:
        var text := String(json.get("text", ""))
        if text.strip_edges() == "":
            print("⚠️ Empty 'text' in ASR reply. Raw body:\n", raw)
        else:
            print("FINAL(%.2fs): %s" % [dur_sec, text])
    else:
        print("⚠️ Non-JSON or unexpected ASR reply. Raw body:\n", raw)


	var text := str(json.get("text", ""))
	print("✅ ASR text:", text)
	return text



#
# ========== AI SERVER CALL ==========
#

func _get_ai_reply(user_text: String) -> Signal:
    return _async_ai_reply(user_text)

@func
async func _async_ai_reply(user_text: String) -> String:
    if server == null:
        push_warning("Server not initialized")
        return ""
    var reply = await server.get_ai_reply(user_text)
    return reply


#
# ========== FISHAUDIO TTS ==========
#

func _tts_generate(ai_text: String) -> Signal:
    return _async_tts(ai_text)

@func
async func _async_tts(ai_text: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	add_child(http)

	var headers = [
		"Authorization: Bearer " + FISH_API_KEY,
		"Content-Type: application/json",
		"model: s1"
	]

	# Use WAV so _wav_bytes_to_stream() keeps working
	var payload := {
		"text": ai_text,
		"format": "wav",
		"sample_rate": SAMPLE_RATE
	}
	var json_body := JSON.stringify(payload).to_utf8_buffer()

	# IMPORTANT: use request_raw for binary-safe upload
	var err := http.request_raw(FISH_TTS_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_warning("❌ Failed to start TTS request: %s" % str(err))
		return PackedByteArray()

	var result = await http.request_completed
	http.queue_free()

	var code := result[1]
	var response_body: PackedByteArray = result[3]

	if code != 200:
		push_warning("⚠️ TTS HTTP code: %d" % code)
		print(response_body.get_string_from_utf8())
		return PackedByteArray()

	print("✅ Received %d bytes of audio from Fish Audio TTS (wav)" % response_body.size())
	return response_body



#
# ========== WAV → AUDIOSTREAM ==========
#

func _wav_bytes_to_stream(wav_bytes: PackedByteArray) -> AudioStreamWAV:
    if wav_bytes.size() < 44:
        return null

    var num_channels = wav_bytes[22] | (wav_bytes[23] << 8)
    var sr = wav_bytes[24] | (wav_bytes[25] << 8) | (wav_bytes[26] << 16) | (wav_bytes[27] << 24)
    var bits_per_sample = wav_bytes[34] | (wav_bytes[35] << 8)

    var data_idx := 36
    while data_idx < wav_bytes.size() - 8:
        if char(wav_bytes[data_idx]) == 'd'.unicode_at(0) \
        and char(wav_bytes[data_idx+1]) == 'a'.unicode_at(0) \
        and char(wav_bytes[data_idx+2]) == 't'.unicode_at(0) \
        and char(wav_bytes[data_idx+3]) == 'a'.unicode_at(0):
            break
        data_idx += 1

    var data_size = wav_bytes[data_idx+4] | (wav_bytes[data_idx+5] << 8) | (wav_bytes[data_idx+6] << 16) | (wav_bytes[data_idx+7] << 24)
    var pcm_start = data_idx + 8
    var pcm_end = pcm_start + data_size
    if pcm_end > wav_bytes.size():
        pcm_end = wav_bytes.size()
    var pcm_data = wav_bytes.slice(pcm_start, pcm_end - pcm_start)

    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = sr
    stream.stereo = (num_channels == 2)
    stream.data = pcm_data
    return stream
