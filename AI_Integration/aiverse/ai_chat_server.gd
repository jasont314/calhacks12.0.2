extends Node

@onready var convo := preload("res://conversation_manager.gd").new()
@onready var jllm  := preload("res://jllm_api.gd").new()

# guard so we don't make overlapping calls to the model
var awaiting_ai := false

# short spam cooldown between trigger attempts
var trigger_cooldown := 0.0
const TRIGGER_COOLDOWN_TIME := 1.0

# block AI from starting a new reply while its voice line is "playing"
var voice_cooldown := 0.0
const VOICE_COOLDOWN_TIME := 4.0  # tune me

# NEW: if players talk while voice_cooldown > 0, we'll flip this to true
# so we know to evaluate after the voice finishes
var pending_after_voice := false

# track whether we're waiting for yes/no or final reply
var pending_mode := ""  # "should_reply" or "final_reply"

func _ready() -> void:
	add_child(convo)
	add_child(jllm)

	convo.set_ai_character("Barack Obama")

	jllm.reply_ready.connect(_on_ai_reply_ready)
	jllm.api_error.connect(_on_ai_error)

	var tester = TestScenarios.new()
	add_child(tester)
	_run_test_scenario(tester)

func _run_test_scenario(tester: TestScenarios) -> void:
	await tester.run_scenario_basic(self)

func _process(delta: float) -> void:
	# tick down trigger cooldown
	if trigger_cooldown > 0.0:
		trigger_cooldown -= delta
	if trigger_cooldown < 0.0:
		trigger_cooldown = 0.0

	# tick down voice cooldown
	var was_voice_blocking := voice_cooldown > 0.0
	if voice_cooldown > 0.0:
		voice_cooldown -= delta
	if voice_cooldown < 0.0:
		voice_cooldown = 0.0

	# IMPORTANT PART:
	# voice_cooldown just ended THIS frame
	# and we previously saw messages during that time
	# and we're not already mid-request
	# and we're not rate-limited
	if was_voice_blocking and voice_cooldown == 0.0:
		if pending_after_voice and not awaiting_ai and trigger_cooldown == 0.0:
			# run a should-reply check now using the latest convo
			_start_should_reply_phase()

		# either way, we've now consumed that pending request
		pending_after_voice = false


func receive_player_message(player_name: String, text: String) -> void:
	# 1. record message
	convo.add_player_message(player_name, text)
	print("[%s]: %s" % [player_name, text])

	# 2. should we try to involve the AI *right now*?

	# if we're already in the middle of a model call:
	if awaiting_ai:
		print("[server] skipping AI check: already waiting on model")
		return

	# if the AI is still 'talking' (voice cooldown):
	if voice_cooldown > 0.0:
		print("[server] skipping AI check: voice cooldown active (AI is talking)")
		# mark that after the voice finishes, we should evaluate again
		pending_after_voice = true
		return

	# anti-spam cooldown:
	if trigger_cooldown > 0.0:
		print("[server] skipping AI check: trigger cooldown active")
		return

	# free to evaluate now
	_start_should_reply_phase()


func _start_should_reply_phase() -> void:
	var judge_ctx = convo.build_should_reply_context()

	awaiting_ai = true
	pending_mode = "should_reply"
	trigger_cooldown = TRIGGER_COOLDOWN_TIME

	jllm.send_message(
		judge_ctx["system_prompt"],
		judge_ctx["messages"],
		50  # expect "yes" or "no"
	)


func _start_final_reply_phase() -> void:
	var reply_ctx = convo.build_reply_context()

	awaiting_ai = true
	pending_mode = "final_reply"

	jllm.send_message(
		reply_ctx["system_prompt"],
		reply_ctx["messages"],
		150  # short multi-sentence answer
	)


func _clean_ai_output(raw_text: String) -> String:
	var t := raw_text.strip_edges()

	var possible_prefixes := [
		"[%s]:" % convo.ai_name,
		"%s:" % convo.ai_name,
		"[%s] :" % convo.ai_name,
		"%s :" % convo.ai_name
	]

	for p in possible_prefixes:
		if t.begins_with(p):
			t = t.substr(p.length()).strip_edges()
			break

	var as_prefix := "As " + convo.ai_name
	if t.begins_with(as_prefix):
		var comma_idx := t.find(",")
		if comma_idx != -1 and comma_idx < 40:
			t = t.substr(comma_idx + 1).strip_edges()

	return t


func _on_ai_reply_ready(text: String) -> void:
	var cleaned := text.strip_edges()

	if pending_mode == "should_reply":
		awaiting_ai = false

		var answer := cleaned.to_lower()
		if answer.begins_with("yes"):
			print("[AI decision] yes → generating reply")
			_start_final_reply_phase()
		else:
			print("[AI decision] no → stay quiet")
		return

	if pending_mode == "final_reply":
		awaiting_ai = false

		var final_text := _clean_ai_output(cleaned)

		# add the AI line to history
		convo.add_ai_message(final_text)

		# show to clients
		_broadcast_ai_message(final_text)

		# start voice cooldown (AI is now talking for VOICE_COOLDOWN_TIME seconds)
		voice_cooldown = VOICE_COOLDOWN_TIME

		# reset any pending-after-voice because we just *did* talk
		pending_after_voice = false

		return

	# fallback
	awaiting_ai = false
	print("[server] unexpected pending_mode: ", pending_mode)


func _on_ai_error(msg: String) -> void:
	print("[AI error]: ", msg)
	awaiting_ai = false


func _broadcast_ai_message(ai_text: String) -> void:
	print("[%s]: %s" % [convo.ai_name, ai_text])
	# later:
	# rpc("receive_message", convo.ai_name, ai_text)
	# plus trigger TTS for that line
