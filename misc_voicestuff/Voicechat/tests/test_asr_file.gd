extends MainLoop

# Usage:
#	godot --headless --path . -s res://tests/test_asr_file.gd sk-APIKEY res://tests/user_input.wav en false
# Args:
#	0: API key (sk-...)
#	1: audio path (res://... or absolute)
#	2: language (optional, e.g. "en")
#	3: ignore_timestamps (optional, "true"/"false", default "true")

const FISH_ASR_URL: String = "https://api.fish.audio/v1/asr"

var _done: bool = false

func _initialize() -> void:
	var args: Array = OS.get_cmdline_args()
	if args.size() < 2:
		push_error("Usage: godot --headless --path . -s res://tests/test_asr_file.gd sk-APIKEY res://path/to.wav [language] [ignore_timestamps]")
		_done = true
		return

	var api_key: String = String(args[0])
	var audio_arg: String = String(args[1])
	var language: String = ""
	if args.size() >= 3:
		language = String(args[2])
	var ignore_ts_str: String = "true"
	if args.size() >= 4:
		ignore_ts_str = String(args[3])

	var fs_audio_path: String = audio_arg
	if audio_arg.begins_with("res://"):
		fs_audio_path = ProjectSettings.globalize_path(audio_arg)

	if not FileAccess.file_exists(fs_audio_path):
		push_error("Audio file not found: " + fs_audio_path)
		_done = true
		return

	var args_psa: PackedStringArray = PackedStringArray([
		"-sS", "-X", "POST", FISH_ASR_URL,
		"-H", "Authorization: Bearer " + api_key,
		"-H", "Expect:",
		"-F", "audio=@"+fs_audio_path,
		"-F", "ignore_timestamps="+ignore_ts_str
	])
	if language != "":
		args_psa.append_array(PackedStringArray(["-F", "language="+language]))

	var out: Array = []
	var code: int = OS.execute("curl", args_psa, out, true) # read_stderr=true
	if code != 0:
		push_error("curl failed (code=" + str(code) + "):\n" + "\n".join(out))
		_done = true
		return

	var resp: String = "\n".join(out)
	var json: Variant = JSON.parse_string(resp)
	if typeof(json) == TYPE_DICTIONARY:
		var text: String = String(json.get("text", ""))
		var dur: String = String(json.get("duration", ""))
		print("Text: " + text)
		print("Duration: " + dur)
		var segs: Array = []
		if json.has("segments") and json["segments"] is Array:
			segs = json["segments"]
		if segs.size() > 0:
			print("Segments:")
			for s in segs:
				if s is Dictionary:
					print("  [" + str(s.get("start","?")) + " -> " + str(s.get("end","?")) + "] " + String(s.get("text","")))
	else:
		print("Non-JSON response:")
		print(resp)

	_done = true

func _process(_delta: float) -> bool:
	return _done
