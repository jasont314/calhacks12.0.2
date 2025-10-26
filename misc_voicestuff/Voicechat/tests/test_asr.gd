extends MainLoop

# 🎤 Live FishAudio ASR (terminal-only, Godot 4.4)
# Run:
#   godot --headless --path . -s res://tests/test_asr.gd sk-YOUR_API_KEY

const FISH_ASR_URL: String = "https://api.fish.audio/v1/asr"
const SAMPLE_RATE: int = 44100

# --- VAD / segmentation tuning ---
const POLL_MS: int = 40
const VAD_THRESHOLD: float = 0.015
const MIN_SPEECH_MS: int = 500
const END_SILENCE_MS: int = 700
const MAX_SEG_SEC: float = 8.0

# --- Runtime state ---
var FISH_API_KEY: String = ""
var capture_bus_idx: int = -1
var capture_effect: AudioEffectCapture = null
var initialized: bool = false
var should_quit: bool = false

# Segment buffers/state
var seg_samples: PackedFloat32Array = PackedFloat32Array()
var seg_started_ms: int = -1
var last_voice_ms: int = -1
var in_voice: bool = false

# Background upload threads so we don't block capture
var upload_threads: Array = []  # Array[Thread] (plain Array is fine)

func _initialize() -> void:
	print("🎤 Live ASR (FishAudio) — starting…")
	var args: Array = OS.get_cmdline_args()
	if args.size() > 0:
		FISH_API_KEY = String(args[0])
	if FISH_API_KEY == "":
		push_error("❌ Missing API key. Usage: godot -s res://tests/test_asr.gd sk-YOUR_API_KEY")
		should_quit = true
		return

	_setup_audio_capture()
	initialized = true
	print("✅ Ready. Start speaking — Ctrl+C to stop.")

func _process(_delta: float) -> bool:
	if should_quit:
		return true
	if not initialized:
		return false

	_pull_and_process_once()
	OS.delay_msec(POLL_MS)
	return false

# ---------------- Audio setup ----------------
func _setup_audio_capture() -> void:
	capture_bus_idx = AudioServer.get_bus_index("CaptureBus")
	if capture_bus_idx == -1:
		print("🔧 Creating 'CaptureBus' …")
		AudioServer.add_bus(AudioServer.get_bus_count())
		capture_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(capture_bus_idx, "CaptureBus")
		var cap: AudioEffectCapture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(capture_bus_idx, cap)

	capture_effect = AudioServer.get_bus_effect(capture_bus_idx, 0)
	if capture_effect == null:
		push_error("❌ AudioEffectCapture missing on 'CaptureBus'. Add one to the first slot.")
		should_quit = true
		return

	print("🎚️ Capture effect: ", capture_effect)

# ---------------- Capture + VAD ----------------
func _pull_and_process_once() -> void:
	if capture_effect == null:
		return

	var frames: int = capture_effect.get_frames_available()
	if frames <= 0:
		_maybe_end_segment_on_silence()
		return

	var buffer: Variant = capture_effect.get_buffer(frames)
	var mono: PackedFloat32Array = PackedFloat32Array()

	if typeof(buffer) == TYPE_PACKED_VECTOR2_ARRAY:
		var stereo: PackedVector2Array = buffer
		mono.resize(stereo.size())
		for i in range(stereo.size()):
			mono[i] = (stereo[i].x + stereo[i].y) * 0.5
	elif typeof(buffer) == TYPE_PACKED_FLOAT32_ARRAY:
		mono = buffer as PackedFloat32Array
	else:
		return

	var rms: float = _rms(mono)
	var now_ms: int = Time.get_ticks_msec()

	if rms >= VAD_THRESHOLD:
		if not in_voice:
			in_voice = true
			seg_samples.resize(0)
			seg_started_ms = now_ms
			print("…listening")
		seg_samples.append_array(mono)
		last_voice_ms = now_ms
	else:
		_maybe_end_segment_on_silence()

	if in_voice and seg_started_ms >= 0:
		var dur_ms_cap: int = now_ms - seg_started_ms
		if float(dur_ms_cap) / 1000.0 >= MAX_SEG_SEC:
			_finalize_segment()

func _maybe_end_segment_on_silence() -> void:
	if not in_voice:
		return
	if last_voice_ms < 0:
		return
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - last_voice_ms) >= END_SILENCE_MS:
		_finalize_segment()

func _finalize_segment() -> void:
	in_voice = false
	var now_ms: int = Time.get_ticks_msec()
	var dur_ms: int = (now_ms - seg_started_ms) if (seg_started_ms >= 0) else 0

	if dur_ms < MIN_SPEECH_MS or seg_samples.size() < 256:
		seg_samples.resize(0)
		seg_started_ms = -1
		last_voice_ms = -1
		return

	var dur_sec: float = float(dur_ms) / 1000.0
	print("⏹️  segment %.2fs — sending…" % dur_sec)

	var wav_bytes: PackedByteArray = _encode_wav_bytes_from_float(seg_samples, SAMPLE_RATE)
	seg_samples.resize(0)
	seg_started_ms = -1
	last_voice_ms = -1

	var t: Thread = Thread.new()
	upload_threads.append(t)
	t.start(Callable(self, "_upload_segment_thread").bind(wav_bytes, dur_sec))

# ---------------- Upload (threaded) ----------------
func _upload_segment_thread(wav_bytes: PackedByteArray, dur_sec: float) -> void:
	var res: Dictionary = _post_asr_binary(FISH_ASR_URL, FISH_API_KEY, wav_bytes)
	if res.has("error"):
		res = _post_asr_via_curl(wav_bytes, FISH_API_KEY)

	var code: int = int(res.get("code", 0))
	var body: PackedByteArray = res.get("body", PackedByteArray())
	if code != 200:
		print("⚠️ ASR HTTP code: ", code)
		print(body.get_string_from_utf8())
		return

	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(json) == TYPE_DICTIONARY:
		var text: String = String(json.get("text", ""))
		print("FINAL(%.2fs): %s" % [dur_sec, text])
	else:
		print("⚠️ Unexpected ASR response format.")

# ---------------- HTTP (binary multipart, no SceneTree) ----------------
func _post_asr_binary(url: String, api_key: String, wav_bytes: PackedByteArray) -> Dictionary:
	var boundary: String = "BoundaryFishGodot123"
	var body: PackedByteArray = PackedByteArray()

	var part: PackedByteArray = ("--" + boundary + "\r\n").to_utf8_buffer()
	body.append_array(part)
	part = "Content-Disposition: form-data; name=\"audio\"; filename=\"segment.wav\"\r\n".to_utf8_buffer()
	body.append_array(part)
	part = "Content-Type: audio/wav\r\n\r\n".to_utf8_buffer()
	body.append_array(part)
	body.append_array(wav_bytes)
	part = ("\r\n--" + boundary + "--\r\n").to_utf8_buffer()
	body.append_array(part)

	# Parse URL
	var scheme_end: int = url.find("://")
	if scheme_end == -1:
		return {"error": "invalid_url"}
	var scheme: String = url.substr(0, scheme_end).to_lower()
	var use_tls: bool = (scheme == "https")
	var port: int = (443 if use_tls else 80)

	var rest: String = url.substr(scheme_end + 3)
	var slash: int = rest.find("/")
	var host: String = (rest if slash == -1 else rest.substr(0, slash))
	var path: String = ("/" if slash == -1 else rest.substr(slash))
	if path == "":
		path = "/"

	var client: HTTPClient = HTTPClient.new()
	var tls_opts: TLSOptions = TLSOptions.client_unsafe() if use_tls else null
	var err: int = client.connect_to_host(host, port, tls_opts)
	if err != OK:
		return {"error": "connect_fail", "code": err}

	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		OS.delay_msec(5)

	var headers: PackedStringArray = PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: multipart/form-data; boundary=" + boundary
	])

	err = client.request_raw(HTTPClient.METHOD_POST, path, headers, body)
	if err != OK:
		return {"error": "request_fail", "code": err}

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(5)

	var code: int = client.get_response_code()
	var resp: PackedByteArray = PackedByteArray()
	if client.has_response():
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk: PackedByteArray = client.read_response_body_chunk()
			if chunk.size() > 0:
				resp.append_array(chunk)
			else:
				OS.delay_msec(5)

	client.close()
	return {"code": code, "body": resp}

# --- curl fallback (robust on headless macOS) ---
func _post_asr_via_curl(wav_bytes: PackedByteArray, api_key: String) -> Dictionary:
	var tmp_path: String = "user://live_asr_segment.wav"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"error": "temp_file_open_failed"}
	f.store_buffer(wav_bytes)
	f.close()

	var out: Array = []
	var args_psa: PackedStringArray = PackedStringArray([
		"-sS", "-X", "POST", FISH_ASR_URL,
		"-H", "Authorization: Bearer " + api_key,
		"-H", "Expect:",
		"-F", "audio=@"+ProjectSettings.globalize_path(tmp_path)+";type=audio/wav",
		"-F", "ignore_timestamps=true"
	])
	var code: int = OS.execute("curl", args_psa, out, true)
	if code != 0:
		return {"error": "curl_failed", "code": code, "stderr": "\n".join(out)}
	var resp_str: String = "\n".join(out)
	var json: Variant = JSON.parse_string(resp_str)
	if typeof(json) == TYPE_DICTIONARY:
		return {"code": 200, "body": resp_str.to_utf8_buffer()}
	return {"error": "non_json_response", "raw": resp_str}

# ---------------- WAV helpers ----------------
func _encode_wav_bytes_from_float(samples: PackedFloat32Array, sr: int) -> PackedByteArray:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: float = clamp(samples[i], -1.0, 1.0)
		var iv: int = int(round(v * 32767.0))
		pcm[i * 2] = iv & 0xFF
		pcm[i * 2 + 1] = (iv >> 8) & 0xFF

	var header: PackedByteArray = PackedByteArray()
	header.append_array("RIFF".to_utf8_buffer())
	header.append_array(_le32(36 + pcm.size()))
	header.append_array("WAVEfmt ".to_utf8_buffer())
	header.append_array(_le32(16))
	header.append_array(_le16(1))      # PCM
	header.append_array(_le16(1))      # mono
	header.append_array(_le32(sr))
	header.append_array(_le32(sr * 2)) # byte rate (mono, 16-bit)
	header.append_array(_le16(2))      # block align
	header.append_array(_le16(16))     # bits per sample
	header.append_array("data".to_utf8_buffer())
	header.append_array(_le32(pcm.size()))
	header.append_array(pcm)
	return header

func _le16(v: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(2)
	b[0] = v & 0xFF
	b[1] = (v >> 8) & 0xFF
	return b

func _le32(v: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(4)
	b[0] = v & 0xFF
	b[1] = (v >> 8) & 0xFF
	b[2] = (v >> 16) & 0xFF
	b[3] = (v >> 24) & 0xFF
	return b


func _rms(samples: PackedFloat32Array) -> float:
	var acc: float = 0.0
	for i in range(samples.size()):
		var s: float = samples[i]
		acc += s * s
	return sqrt(acc / max(1, samples.size()))
