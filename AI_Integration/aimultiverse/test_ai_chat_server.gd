extends Node
class_name TestAIChatServer

var chat_history: ChatHistory
var bots: Array = []            # [BotController, ...]
var tts_manager: TTSManager

# mic lock so bots don't talk over each other AFTER someone is already speaking
var global_voice_lock_time := 0.0
var global_voice_owner := ""

# pre-lock so two bots don't both generate a reply at once
var pending_generation_owner := ""  # "" means nobody has pre-claimed

const GLOBAL_VOICE_FALLBACK := 2.5  # seconds if we can't get clip length
var start_time := 0.0


func _ready() -> void:
	set_process(true)
	start_time = Time.get_unix_time_from_system()

	# shared chat history
	chat_history = ChatHistory.new()
	add_child(chat_history)

	# TTS manager
	tts_manager = TTSManager.new()
	add_child(tts_manager)

	# --- BOTS ---

	# Barack Obama
	create_bot(
		"Barack Obama",
		"""You are Barack Obama, former President of the United States.
You are calm, thoughtful, measured, and policy-minded.
You try to cool people down, not escalate.
Keep replies short (1-3 sentences). Avoid explicit calls for violence or anything illegal."""
	)

	# Donald Trump
	create_bot(
		"Donald Trump",
		"""You are Donald Trump, former President.
You're blunt, confident, hypey. You speak in punchy, memorable lines.
You praise yourself and your team. You avoid slurs, threats, or explicit incitement.
Keep it to 1-3 sentences."""
	)

	# SpongeBob SquarePants
	create_bot(
		"SpongeBob SquarePants",
		"""You are SpongeBob SquarePants.
You are hyper-optimistic, playful, excitable, and friendly.
You respond with goofy enthusiasm and weirdly sincere encouragement.
You're nonviolent, harmless, and you never encourage anything dangerous or illegal.
Keep replies super short (1-2 sentences). Use light silliness, mild sea puns, and occasional all-caps excitement."""
	)

	# Peter Griffin
	create_bot(
		"Peter Griffin",
		"""You are Peter Griffin.
You're loud, impulsive, kinda clueless, and you go on weird little rants.
You crack jokes and act overconfident even when you're wrong.
Keep replies short (1-2 sentences). Stay goofy, not hateful, and don't encourage illegal stuff."""
	)

	# scenario drive
	var tester := TestScenarios.new()
	add_child(tester)
	await tester.run_scenario_basic(self)


func _process(delta: float) -> void:
	# tick down current speaker's mic lock
	if global_voice_lock_time > 0.0:
		global_voice_lock_time -= delta
		if global_voice_lock_time <= 0.0:
			global_voice_owner = ""
			_print_ts("[server] mic released")

			# mic is released, so nobody has next-turn priority anymore
			pending_generation_owner = ""

			# let bots who were waiting know they can try again
			for b in bots:
				b.on_mic_released()


#
# Per-bot voice config for TTS
#
func _get_voice_config_for(bot_name: String) -> Dictionary:
	match bot_name:
		"Donald Trump":
			return {
				"model_id": "s1",
				"reference_id": "5196af35f6ff4a0dbf541793fc9f2157", # Trump
				"format": "mp3"
			}
		"Barack Obama":
			return {
				"model_id": "s1",
				"reference_id": "4ce7e917cedd4bc2bb2e6ff3a46acaa1", # Obama
				"format": "mp3"
			}
		"SpongeBob SquarePants":
			return {
				"model_id": "s1",
				"reference_id": "54e3a85ac9594ffa83264b8a494b901b", # SpongeBob
				"format": "mp3"
			}
		"Peter Griffin":
			return {
				"model_id": "s1",
				"reference_id": "d75c270eaee14c8aa1e9e980cc37cf1b", # Peter
				"format": "mp3"
			}
		_:
			return {
				"model_id": "s1",
				"reference_id": "",
				"format": "mp3"
			}


#
# Spawn a bot, wire it up to server + chat + api + persona
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
# timestamp utils
#
func _now_ts() -> float:
	return Time.get_unix_time_from_system() - start_time

func _print_ts(msg: String) -> void:
	print("[%.2fs] %s" % [_now_ts(), msg])


#
# Player (or scenario) says something into chat
#
func receive_player_message(player_name: String, text: String) -> void:
	chat_history.add_message("user", player_name, text)
	_print_ts("[%s]: %s" % [player_name, text])

	# tell every bot this message happened
	for bot in bots:
		bot.on_player_message(player_name, text)


#
# A bot has produced final text and wants to "say it in the room"
#
func broadcast_ai_message(bot_name: String, ai_text: String) -> void:
	# log visibly and save to transcript
	chat_history.add_message("assistant", bot_name, ai_text)
	_print_ts("[%s]: %s" % [bot_name, ai_text])

	# TTS for this bot
	var voice_cfg := _get_voice_config_for(bot_name)
	var clip_len := await tts_manager.speak(bot_name, ai_text, voice_cfg)

	if clip_len <= 0.0:
		clip_len = GLOBAL_VOICE_FALLBACK

	_print_ts("\t[server] mic claimed by %s for %.2fs" % [bot_name, clip_len])

	# Lock mic for duration of speech playback
	claim_mic_for_bot(bot_name, clip_len)

	# Let other bots "hear" what was said so they can react later
	for other in bots:
		if other.bot_name == bot_name:
			continue
		other.on_player_message(bot_name, ai_text)


#
# ---------- MIC / TURN-TAKING HELPERS ----------
#

# Called by a bot right after it gets "yes" from phase 1,
# to reserve the right to answer next so two bots don't both generate.
func reserve_generation(bot_name: String) -> bool:
	# if nobody is talking AND nobody has already reserved the next turn:
	if global_voice_lock_time <= 0.0 and pending_generation_owner == "":
		pending_generation_owner = bot_name
		# _print_ts("\t[server] generation reserved by %s" % bot_name)
		return true

	# if the same bot already reserved, also allow it
	if pending_generation_owner == bot_name:
		return true

	# someone else already reserved
	return false

# Check if a bot is allowed to jump in right now.
func can_bot_take_mic(bot_name: String) -> bool:
	# If someone is currently speaking out loud, only that bot can continue.
	if global_voice_lock_time > 0.0:
		return global_voice_owner == bot_name

	# No one is actively speaking, but maybe someone "reserved" the next turn.
	if pending_generation_owner != "" and pending_generation_owner != bot_name:
		return false

	# Otherwise it's open.
	return true


# Actually claim the mic for playback time.
func claim_mic_for_bot(bot_name: String, seconds: float) -> void:
	global_voice_owner = bot_name
	global_voice_lock_time = seconds

	# once the bot is actually "on mic", clear the reservation if it was theirs
	if pending_generation_owner == bot_name:
		pending_generation_owner = ""
