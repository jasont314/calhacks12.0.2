extends Node
class_name TestAIChatServer

var chat_history: ChatHistory
var bots: Array = []  # [BotController, BotController, ...]

# global mic lock so bots don't all talk at once
var global_voice_lock_time := 0.0
var global_voice_owner := ""
const GLOBAL_VOICE_COOLDOWN := 2.5

var start_time_ms := 0


func _ready() -> void:
	set_process(true)
	start_time_ms = Time.get_ticks_msec()

	# 1) shared chat history
	chat_history = ChatHistory.new()
	add_child(chat_history)

	# 2) spawn bots via helper
	create_bot(
		"Barack Obama",
		"""You are Barack Obama, former President of the United States.
You are calm, thoughtful, measured, and policy-minded.
You try to cool people down, not escalate.
Keep replies short (1-3 sentences). Avoid explicit calls for violence or anything illegal."""
	)

	create_bot(
		"Donald Trump",
		"""You are Donald Trump, former President.
You're blunt, confident, hypey. You speak in punchy, memorable lines.
You praise yourself and your team. You avoid slurs, threats, or explicit incitement.
Keep it to 1-3 sentences."""
	)

	# 3) run a test scenario
	var tester := TestScenarios.new()
	add_child(tester)
	await tester.run_scenario_bots_only(self)
	# or run_scenario_basic(self)


func _process(delta: float) -> void:
	if global_voice_lock_time > 0.0:
		global_voice_lock_time -= delta
		if global_voice_lock_time <= 0.0:
			global_voice_owner = ""
			print("\t[%0.2fs] [server] mic released" % _now_s())

			# NEW: ping bots that were waiting on mic
			for b in bots:
				b.on_mic_released()


#
# helper to spawn + wire a bot
#
func create_bot(bot_name: String, persona_prompt: String) -> void:
	var api := JLLMApi.new()
	add_child(api)

	var bot := BotController.new()
	bot.server_ref = self
	bot.chat_history = chat_history
	bot.jllm_api = api
	bot.bot_name = bot_name
	bot.persona_prompt = persona_prompt

	add_child(bot)
	bots.append(bot)


#
# called by scenario / real clients when a human types
#
func receive_player_message(player_name: String, text: String) -> void:
	print("[%0.2fs] [%s]: %s" % [_now_s(), player_name, text])

	chat_history.add_message("user", player_name, text)

	for bot in bots:
		bot.on_player_message(player_name, text)


#
# called BY BOTS when they speak to the room
#
func broadcast_ai_message(bot_name: String, ai_text: String) -> void:
	print("[%0.2fs] [%s]: %s" % [_now_s(), bot_name, ai_text])

	chat_history.add_message("assistant", bot_name, ai_text)

	# tell other bots this line just happened
	for other in bots:
		if other.bot_name == bot_name:
			continue
		other.on_player_message(bot_name, ai_text)

	# debug mic state
	print("\t[%0.2fs] [server] %s now has the mic for %.1f sec" %
		[_now_s(), bot_name, GLOBAL_VOICE_COOLDOWN])


#
# ---- GLOBAL MIC LOCK HELPERS ----
#
func can_bot_take_mic(bot_name: String) -> bool:
	if global_voice_lock_time <= 0.0:
		return true
	if global_voice_owner == bot_name:
		return true
	return false


func claim_mic_for_bot(bot_name: String) -> void:
	global_voice_owner = bot_name
	global_voice_lock_time = GLOBAL_VOICE_COOLDOWN
	print("\t[%0.2fs] [server] mic claimed by %s" % [_now_s(), bot_name])


#
# timestamp helper
#
func _now_s() -> float:
	var now_ms := Time.get_ticks_msec()
	return float(now_ms - start_time_ms) / 1000.0
