extends Node
class_name AIChatServer

var chat_history: ChatHistory
var bots: Array = []          # [BotController, ...]
var tts_manager: TTSManager

# mic state
var global_voice_lock_time := 0.0
var global_voice_owner := ""

# pre-turn reservation so they don't both decide to talk at once
var pending_generation_owner := ""

var start_time := 0.0

# fallback if TTS didn't report length (we still use it briefly)
const GLOBAL_VOICE_FALLBACK := 2.5


func _ready() -> void:
	set_process(true)
	start_time = Time.get_unix_time_from_system()

	# shared chat
	chat_history = ChatHistory.new()
	add_child(chat_history)

	# TTS
	tts_manager = TTSManager.new()
	add_child(tts_manager)

	# listen for audio lifecycle so we can own / release mic
	tts_manager.line_started.connect(_on_tts_line_started)
	tts_manager.line_finished.connect(_on_tts_line_finished)

	# bots
	_create_bot(
		"Barack Obama",
		"""You are Barack Obama, former President of the United States.
You are calm, thoughtful, measured, and policy-minded.
You try to cool people down, not escalate.
Keep replies short (1-3 sentences). Avoid explicit calls for violence or anything illegal."""
	)

	_create_bot(
		"Donald Trump",
		"""You are Donald Trump, former President.
You're blunt, confident, hypey. You speak in punchy, memorable lines.
You praise yourself and your team. You avoid slurs, threats, or explicit incitement.
Keep it to 1-3 sentences."""
	)

	_create_bot(
		"SpongeBob",
		"""You are SpongeBob SquarePants.
You're hyper-positive, excitable, a little naive, and extremely enthusiastic.
You react like everything is a big cartoon adventure.
Keep it bouncy and silly, but safe for humans. 1-3 short sentences max."""
	)

	_create_bot(
		"Peter Griffin",
		"""You are Peter Griffin from Family Guy.
You're sarcastic, impulsive, kinda dumb in a lovable way. You joke, you complain,
you turn serious stuff into something ridiculous.
Stay PG-13, avoid slurs, threats, or anything illegal. Keep it 1-3 sentences."""
	)


func run_debug_scenario() -> void:
	# optional: scripted test
	var tester := TestScenarios.new()
	add_child(tester)
	await tester.run_scenario_basic(self)


func _process(delta: float) -> void:
	# tick down mic timer
	if global_voice_lock_time > 0.0:
		global_voice_lock_time -= delta
		if global_voice_lock_time <= 0.0 and global_voice_owner != "":
			# safety fallback in case audio never fired "finished"
			_release_mic("timeout fallback")


#
# Bot creation
#
func _create_bot(bot_name: String, persona_prompt: String) -> void:
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
# Helpers for printing with timestamp
#
func _now_ts() -> float:
	return Time.get_unix_time_from_system() - start_time

func _print_ts(msg: String, debug := false) -> void:
	var prefix := ""
	if debug:
		prefix = "\t"  # indent debug/system stuff
	print("[%.2fs] %s%s" % [_now_ts(), prefix, msg])


#
# Entry point: called by WSListener or scenario when a human speaks
#
func receive_player_message(player_name: String, text: String) -> void:
	chat_history.add_message("user", player_name, text)
	_print_ts("[%s]: %s" % [player_name, text])

	for bot in bots:
		bot.on_player_message(player_name, text)


#
# Called by a bot when it actually has final reply text
#
func broadcast_ai_message(bot_name: String, ai_text: String) -> void:
	# 1. Log + store in transcript immediately
	chat_history.add_message("assistant", bot_name, ai_text)
	_print_ts("[%s]: %s" % [bot_name, ai_text])

	# 2. Queue the voice line for playback
	var voice_cfg := _get_voice_config_for(bot_name)
	tts_manager.enqueue_line(bot_name, ai_text, voice_cfg)

	# 3. Tell the other bots "this just got said"
	for other in bots:
		if other.bot_name == bot_name:
			continue
		other.on_player_message(bot_name, ai_text)


#
# Voice config per bot
#
func _get_voice_config_for(bot_name: String) -> Dictionary:
	match bot_name:
		"Donald Trump":
			return {
				"model_id": "s1",
				"reference_id": "5196af35f6ff4a0dbf541793fc9f2157",
				"format": "mp3"
			}
		"Barack Obama":
			return {
				"model_id": "s1",
				"reference_id": "4ce7e917cedd4bc2bb2e6ff3a46acaa1",
				"format": "mp3"
			}
		"SpongeBob":
			return {
				"model_id": "s1",
				"reference_id": "54e3a85ac9594ffa83264b8a494b901b",
				"format": "mp3"
			}
		"Peter Griffin":
			return {
				"model_id": "s1",
				"reference_id": "d75c270eaee14c8aa1e9e980cc37cf1b",
				"format": "mp3"
			}
		_:
			return {
				"model_id": "s1",
				"reference_id": "",
				"format": "mp3"
			}


#
# ---------- Mic / turn-taking logic ----------
#

# after "yes", bot tries to reserve the next turn to talk
# returns true if it won, false if someone else already reserved / is speaking
func reserve_generation(bot_name: String) -> bool:
	# if someone is already audibly talking, you can't reserve
	if global_voice_lock_time > 0.0:
		return false

	# nobody is speaking: first caller wins
	if pending_generation_owner == "":
		pending_generation_owner = bot_name
		return true

	# already reserved by someone else or same bot
	return pending_generation_owner == bot_name


# can this bot *attempt* to talk right now?
func can_bot_take_mic(bot_name: String) -> bool:
	# active speaker still talking?
	if global_voice_lock_time > 0.0:
		return (global_voice_owner == bot_name)

	# nobody talking, but someone reserved next turn?
	if pending_generation_owner != "" and pending_generation_owner != bot_name:
		return false

	return true


# helper: find the BotController for a given bot_name
func _find_bot(name: String) -> BotController:
	for b in bots:
		if b.bot_name == name:
			return b
	return null


# when audio for a line actually STARTS playing
func _on_tts_line_started(bot_name: String, clip_len: float) -> void:
	# claim mic for whoever just started playing
	global_voice_owner = bot_name
	global_voice_lock_time = max(clip_len, GLOBAL_VOICE_FALLBACK)
	pending_generation_owner = ""  # they've cashed in their reservation

	_print_ts("[server] mic claimed by %s for %.2fs" % [bot_name, global_voice_lock_time], true)

	# tell that bot "you are actively talking for clip_len seconds; don't talk again yet"
	var bot := _find_bot(bot_name)
	if bot:
		bot.notify_tts_started(clip_len)


# when audio for that line FINISHES playing
func _on_tts_line_finished(bot_name: String) -> void:
	# let that bot know it's allowed to speak again
	var bot := _find_bot(bot_name)
	if bot:
		bot.notify_tts_finished()

	_release_mic("finished")


func _release_mic(reason: String) -> void:
	if global_voice_owner != "":
		_print_ts("[server] mic released (%s)" % reason, true)

	global_voice_owner = ""
	global_voice_lock_time = 0.0
	pending_generation_owner = ""

	# wake all bots that were waiting so they can reconsider speaking
	for b in bots:
		b.on_mic_released()
