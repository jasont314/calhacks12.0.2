extends Node
class_name TTSManager

const FISH_API_KEY := "95b6acee27c042d89c8ad0102a14986b"  # <-- put your real Fish Audio API key here
const TTS_URL := "https://api.fish.audio/v1/tts"

#
# Public: server calls this after a bot speaks.
# We return how long the audio clip is (seconds),
# so the server can keep the mic locked.
#
# bot_name: "Barack Obama", "Donald Trump", etc.
# line_text: what the bot said in text
# voice_cfg: {
#     "model_id": "s1",
#     "format": "mp3",
#     "reference_id": "4ce7e917cedd4bc2bb2e6ff3a46acaa1"
# }
#
func speak(bot_name: String, line_text: String, voice_cfg: Dictionary) -> float:
	var http := HTTPRequest.new()
	add_child(http)
	return await _do_tts_request(http, bot_name, line_text, voice_cfg)


#
# Internal helper: actually does the HTTP call, builds AudioStream, plays it.
#
func _do_tts_request(http: HTTPRequest, bot_name: String, line_text: String, voice_cfg: Dictionary) -> float:
	var model_id     = voice_cfg.get("model_id", "s1")
	var fmt          = voice_cfg.get("format", "mp3")
	var reference_id = voice_cfg.get("reference_id", "")

	# Fish Audio requires these headers:
	#   Authorization: Bearer <token>
	#   Content-Type: application/json
	#   model: <model_id>
	var headers := [
		"Authorization: Bearer " + FISH_API_KEY,
		"Content-Type: application/json",
		"model: " + model_id,
	]

	# We send ONLY the core fields:
	#   text, format, reference_id
	# No temperature, prosody, etc.
	var body_dict := {
		"text": line_text,
		"format": fmt,
		"reference_id": reference_id,
	}

	var err := http.request(
		TTS_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body_dict)
	)

	if err != OK:
		print("[TTS fatal error for %s]: request() failed code %s" % [bot_name, str(err)])
		http.queue_free()
		return 0.0

	# Wait for response from Fish Audio.
	# request_completed gives: [result_code, status_code, headers, body]
	var result = await http.request_completed
	var result_code = result[0]
	var status_code = result[1]
	var raw_body: PackedByteArray = result[3]

	http.queue_free()

	# Non-2xx from Fish? Bail.
	if result_code != OK or status_code < 200 or status_code >= 300:
		print("[TTS error for %s]: TTS HTTP %s" % [bot_name, str(status_code)])
		return 0.0

	# At this point raw_body should literally be MP3 bytes.
	var stream := AudioStreamMP3.new()
	stream.data = raw_body

	# Play it right now.
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)

	player.play()

	# Length used to lock mic. If Godot can't read it, fallback later.
	var clip_len := 0.0
	var reported_len := stream.get_length()
	if reported_len > 0.0:
		clip_len = reported_len
	else:
		clip_len = 2.5  # fallback guess

	return clip_len
