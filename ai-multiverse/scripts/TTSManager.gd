extends Node
class_name TTSManager

signal line_started(bot_name: String, clip_len: float)
signal line_finished(bot_name: String)

const FISH_API_KEY := "95b6acee27c042d89c8ad0102a14986b"  # your Fish API key
const TTS_URL := "https://api.fish.audio/v1/tts"

var _queue: Array = []           # [{bot_name, text, voice_cfg}]
var _busy := false               # are we currently playing audio?
var _current_player: AudioStreamPlayer = null


# Public: AIChatServer calls this instead of speak()
func enqueue_line(bot_name: String, line_text: String, voice_cfg: Dictionary) -> void:
	_queue.append({
		"bot_name": bot_name,
		"text": line_text,
		"voice_cfg": voice_cfg,
	})
	_try_play_next()


func _try_play_next() -> void:
	if _busy:
		return
	if _queue.is_empty():
		return

	_busy = true
	var item: Dictionary = _queue.pop_front()
	_play_item(item)


# Actually fetch TTS, create AudioStream, play it, wait until done,
# emit signals, then move on to next in queue.
func _play_item(item: Dictionary) -> void:
	var bot_name = item["bot_name"]
	var text = item["text"]
	var voice_cfg = item["voice_cfg"]

	# 1. request audio from Fish
	var result := await _fetch_tts_audio(bot_name, text, voice_cfg)
	var stream: AudioStreamMP3 = result.get("stream", null)
	var clip_len: float = result.get("clip_len", 2.5)

	if stream == null:
		# failed TTS – still emit finished so queue can move
		print("[TTS error for %s]: no audio stream" % bot_name)
		emit_signal("line_started", bot_name, clip_len)
		emit_signal("line_finished", bot_name)
		_busy = false
		_try_play_next()
		return

	# 2. create / play player
	_current_player = AudioStreamPlayer.new()
	_current_player.stream = stream
	
	# Per-character gain tweaks
	match bot_name:
		"Peter Griffin":
			_current_player.volume_db = 6.0  # louder
		"Barack Obama":
			_current_player.volume_db = 0.0  # normal
		"Donald Trump":
			_current_player.volume_db = 0.0
		"SpongeBob":
			_current_player.volume_db = 0.0
		_:
			_current_player.volume_db = 0.0
		
	add_child(_current_player)

	# Let server know this bot is "on mic" for clip_len seconds
	emit_signal("line_started", bot_name, clip_len)

	_current_player.play()

	# 3. wait for playback to end
	# AudioStreamPlayer in Godot 4 has "finished" signal.
	await _current_player.finished

	# 4. cleanup
	_current_player.queue_free()
	_current_player = null

	# tell server we're done talking
	emit_signal("line_finished", bot_name)

	_busy = false
	_try_play_next()


#
# Low-level HTTP -> Fish Audio
#
func _fetch_tts_audio(bot_name: String, line_text: String, voice_cfg: Dictionary) -> Dictionary:
	var model_id     = voice_cfg.get("model_id", "s1")
	var fmt          = voice_cfg.get("format", "mp3")
	var reference_id = voice_cfg.get("reference_id", "")

	var http := HTTPRequest.new()
	add_child(http)

	var headers := [
		"Authorization: Bearer " + FISH_API_KEY,
		"Content-Type: application/json",
		"model: " + model_id,
	]

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
		return {
			"stream": null,
			"clip_len": 0.0,
		}

	var res = await http.request_completed
	var result_code = res[0]
	var status_code = res[1]
	var raw_body: PackedByteArray = res[3]

	http.queue_free()

	if result_code != OK or status_code < 200 or status_code >= 300:
		print("[TTS error for %s]: TTS HTTP %s" % [bot_name, str(status_code)])
		return {
			"stream": null,
			"clip_len": 0.0,
		}

	# Build mp3 stream
	var stream := AudioStreamMP3.new()
	stream.data = raw_body

	var clip_len := stream.get_length()
	if clip_len <= 0.0:
		clip_len = 2.5  # fallback guess

	return {
		"stream": stream,
		"clip_len": clip_len,
	}
