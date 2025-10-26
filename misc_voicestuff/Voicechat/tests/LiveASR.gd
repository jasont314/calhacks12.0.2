extends Node
class_name LiveASR

# LiveASR: low-latency "near-real-time" transcription using short mic segments.
# Usage:
#   var asr := LiveASR.new()
#   asr.fish_api_key = "sk-xxxx"
#   add_child(asr)
#   asr.start()

signal partial(text: String)
signal final(text: String, duration_sec: float)
signal error(message: String)

# -------- Config --------
var fish_api_key: String = ""
var fish_asr_url: String = "https://api.fish.audio/v1/asr"

var sample_rate: int = 44100
var chunk_ms: int = 40                 # capture poll granularity
var max_segment_sec: float = 8.0       # safety upper bound per utterance
var min_speech_ms: int = 200           # avoid tiny blips
var end_silence_ms: int = 400          # time w/o speech to end segment
var vad_threshold: float = 0.015       # tweak per mic; ~RMS gate
var curl_fallback: bool = true         # use curl if TLS fails in headless

# -------- Internals --------
var _bus_idx: int = -1
var _cap: AudioEffectCapture = null
var _mic_player: AudioStreamPlayer = null
var _timer: Timer = null

var _speech_started_ms: int = 0
var _last_voice_ms: int = 0
var _accum: PackedFloat32Array = PackedFloat32Array()
var _rolling_text: String = ""
var _running: bool = false

func start() -> void:
	if fish_api_key == "":
		_emit_error("Missing fish_api_key")
		return

	# Ensure capture bus + effect
	_bus_idx = AudioServer.get_bus_index("CaptureBus")
	if _bus_idx == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_bus_idx, "CaptureBus")
		AudioServer.add_bus_effect(_bus_idx, AudioEffectCapture.new())

	# Mic source -> CaptureBus
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = "CaptureBus"
		add_child(_mic_player)
		_mic_player.play()

	_cap = AudioServer.get_bus_effect(_bus_idx, 0)
	if _cap == null:
		_emit_error("AudioEffectCapture not found/attached")
		return

	# Poll timer
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = false
		_timer.wait_time = float(chunk_ms) / 1000.0
		add_child(_timer)
		_timer.timeout.connect(_on_tick)

	_accum = PackedFloat32Array()
	_speech_started_ms = 0
	_last_voice_ms = 0
	_rolling_text = ""
	_running = true
	_timer.start()
	print("🎤 LiveASR started (VAD threshold=%.3f)" % vad_threshold)

func stop() -> void:
	_running = false
	if _timer:
		_timer.stop()

func _on_tick() -> void:
	if not _running or _cap == null:
		return

	# Pull available frames
	var frames := _cap.get_frames_available()
	if frames <= 0:
		# If we are in speech, check for end-silence end
		_check_maybe_finalize()
		return

	var buf := _cap.get_buffer(frames)
	var mono := _float_mono(buf)
	if mono.size() == 0:
		_check_maybe_finalize()
		return

	# Append to segment buffer
	_append_audio(_accum, mono)

	# Simple VAD
	var rms := _rms(mono)
	var now_ms := Time.get_ticks_msec()
	if rms >= vad_threshold:
		if _speech_started_ms == 0:
			_speech_started_ms = now_ms
		_last_voice_ms = now_ms
	else:
		# silence frame
		pass

	# Emit "partial" from a cheap heuristic (client-side), optional
	if _accum.size() > 0 and (_last_voice_ms - _speech_started_ms) > min_speech_ms:
		# There's no real-time partial from FishAudio here; we just hint text is coming.
		# (You can integrate a local VAD/NLP for smarter partials if needed.)
		emit_signal("partial", _rolling_text)

	# Safety: cap max segment
	var seg_dur := float(_accum.size()) / float(sample_rate)
	if seg_dur >= max_segment_sec:
		_finalize_segment()
		return

	# Silence-based finalize
	_check_maybe_finalize()

func _check_maybe_finalize() -> void:
	if _speech_started_ms == 0:
		return
	var now_ms := Time.get_ticks_msec()
	var since_voice := now_ms - _last_voice_ms
	if since_voice >= end_silence_ms:
		_finalize_segment()

func _finalize_segment() -> void:
	if _accum.size() == 0:
		_reset_segment_state()
		return

	var dur := float(_accum.size()) / float(sample_rate)
	var wav := _encode_wav_bytes_from_float(_accum, sample_rate)

	# Call ASR
	var res := _post_asr_binary(fish_asr_url, fish_api_key, wav)
	if res.has("error") and curl_fallback:
		print("⚠️ HTTPClient failed (", res["error"], "), trying curl fallback…")
		res = _post_asr_via_curl(wav, fish_api_key)

	var code: int = int(res.get("code", 0))
	var body: PackedByteArray = res.get("body", PackedByteArray())
	if code != 200:
		_emit_error("ASR HTTP code: %d\n%s" % [code, body.get_string_from_utf8()])
	else:
		var j := JSON.parse_string(body.get_string_from_utf8())
		if typeof(j) == TYPE_DICTIONARY:
			var text := String(j.get("text", ""))
			_rolling_text += ("" if _rolling_text == "" else " ") + text
			emit_signal("final", text, dur)
		else:
			_emit_error("Unexpected ASR response")

	_reset_segment_state()

func _reset_segment_state() -> void:
	_accum = PackedFloat32Array()
	_speech_started_ms = 0
	_last_voice_ms = 0

# ========== Helpers ==========

func _emit_error(msg: String) -> void:
	push_warning(msg)
	emit_signal("error", msg)

func _float_mono(buffer: Variant) -> PackedFloat32Array:
	var mono := PackedFloat32Array()
	if typeof(buffer) == TYPE_PACKED_VECTOR2_ARRAY:
		var st: PackedVector2Array = buffer
		mono.resize(st.size())
		for i in st.size():
			mono[i] = (st[i].x + st[i].y) * 0.5
	elif typeof(buffer) == TYPE_PACKED_FLOAT32_ARRAY:
		mono = buffer
	return mono

func _append_audio(dst: PackedFloat32Array, src: PackedFloat32Array) -> void:
	var old := dst.size()
	dst.resize(old + src.size())
	for i in src.size():
		dst[old + i] = src[i]

func _rms(samples: PackedFloat32Array) -> float:
	var s: float = 0.0
	for i in samples.size():
		s += samples[i] * samples[i]
	return sqrt(s / max(1, samples.size()))

# WAV (16-bit PCM) — pay attention to "WAVE" + "fmt " split
func _encode_wav_bytes_from_float(samples: PackedFloat32Array, sr: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		var v: float = clamp(samples[i], -1.0, 1.0)
		var iv: int = int(round(v * 32767.0))
		pcm[i * 2] = iv & 0xFF
		pcm[i * 2 + 1] = (iv >> 8) & 0xFF

	var header := PackedByteArray()
	header.append_array("RIFF".to_utf8_buffer())
	header.append_array(_le32(36 + pcm.size()))
	header.append_array("WAVE".to_utf8_buffer())
	header.append_array("fmt ".to_utf8_buffer())
	header.append_array(_le32(16))
	header.append_array(_le16(1))      # PCM
	header.append_array(_le16(1))      # mono
	header.append_array(_le32(sr))
	header.append_array(_le32(sr * 2)) # byte rate = sr*ch*bits/8
	header.append_array(_le16(2))      # block align = ch*bits/8
	header.append_array(_le16(16))     # bits
	header.append_array("data".to_utf8_buffer())
	header.append_array(_le32(pcm.size()))
	header.append_array(pcm)
	return header

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

# ---- HTTP (binary multipart); falls back to curl in headless macOS ----

func _post_asr_binary(url: String, key: String, wav: PackedByteArray) -> Dictionary:
	var boundary := "BoundaryFishGodot123"
	var body := PackedByteArray()
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"audio\"; filename=\"seg.wav\"\r\n".to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"ignore_timestamps\"\r\n\r\ntrue\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())

	# Parse URL
	var scheme_end := url.find("://")
	if scheme_end == -1:
		return {"error": "invalid_url"}
	var scheme := url.substr(0, scheme_end).to_lower()
	var use_tls := (scheme == "https")
	var port := 443 if use_tls else 80
	var rest := url.substr(scheme_end + 3)
	var slash := rest.find("/")
	var host := (rest if slash == -1 else rest.substr(0, slash))
	var path := ("/" if slash == -1 else rest.substr(slash))
	if path == "":
		path = "/"

	var client := HTTPClient.new()
	var tls := TLSOptions.client_unsafe() if use_tls else null
	var err := client.connect_to_host(host, port, tls)
	if err != OK:
		return {"error": "connect_fail", "code": err}

	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		OS.delay_msec(10)

	var headers := PackedStringArray([
		"Authorization: Bearer " + key,
		"Content-Type: multipart/form-data; boundary=" + boundary
	])

	err = client.request_raw(HTTPClient.METHOD_POST, path, headers, body)
	if err != OK:
		return {"error": "request_fail", "code": err}

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(10)

	var code := client.get_response_code()
	var resp := PackedByteArray()
	if client.has_response():
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk := client.read_response_body_chunk()
			if chunk.size() > 0:
				resp.append_array(chunk)
			else:
				OS.delay_msec(10)

	client.close()
	return {"code": code, "body": resp}

func _post_asr_via_curl(wav: PackedByteArray, key: String) -> Dictionary:
	var tmp := "user://seg_tmp.wav"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"error": "temp_file_open_failed"}
	f.store_buffer(wav)
	f.close()

	var out := []
	var args := PackedStringArray([
		"-sS", "-X", "POST", fish_asr_url,
		"-H", "Authorization: Bearer " + key,
		"-H", "Expect:",
		"-F", "audio=@"+ProjectSettings.globalize_path(tmp)+";type=audio/wav",
		"-F", "ignore_timestamps=true"
	])
	var code := OS.execute("curl", args, out, true)
	if code != 0:
		return {"error": "curl_failed", "code": code, "stderr": "\n".join(out)}
	var resp_str := "\n".join(out)
	var json := JSON.parse_string(resp_str)
	if typeof(json) == TYPE_DICTIONARY:
		return {"code": 200, "body": resp_str.to_utf8_buffer()}
	return {"error": "non_json_response", "raw": resp_str}
