extends Node
class_name BotController

var server_ref: AIChatServer
var chat_history: ChatHistory
var jllm_api: JLLMApi
var bot_name: String = ""
var persona_prompt: String = ""

# state / turn-taking
var awaiting_ai := false
var pending_mode := ""               # "should_reply" | "final_reply"
var pending_after_voice := false     # tried to talk while still speaking
var pending_after_mic := false       # tried to talk while someone else had mic

var voice_cooldown_timer := 0.0
var trigger_cooldown_timer := 0.0

# tuning knobs
const TRIGGER_COOLDOWN := 1.0  # delay between "should I reply?" polls
const DECISION_TAIL_LENGTH := 6
const REPLY_TAIL_LENGTH := 12


func _ready() -> void:
	set_process(true)
	jllm_api.reply_ready.connect(_on_model_reply_ready)
	jllm_api.api_error.connect(_on_model_error)


func _process(delta: float) -> void:
	if voice_cooldown_timer > 0.0:
		voice_cooldown_timer -= delta
		if voice_cooldown_timer <= 0.0 and pending_after_voice:
			pending_after_voice = false
			_try_trigger_ai_check()

	if trigger_cooldown_timer > 0.0:
		trigger_cooldown_timer -= delta


# server tells me my audio actually started (clip_len seconds long)
func notify_tts_started(clip_len: float) -> void:
	# lock me for length of my spoken line, so I don't generate more lines mid-speech
	voice_cooldown_timer = clip_len + 0.5
	pending_after_voice = false


# server tells me my audio actually finished
func notify_tts_finished() -> void:
	voice_cooldown_timer = 0.0


# called whenever ANYONE says something (players OR bots)
func on_player_message(speaker_name: String, text: String) -> void:
	# if we're already mid-call to LLM
	if awaiting_ai:
		print("\t[%s bot] skipping AI check: already waiting on model" % bot_name)
		return

	# if someone else currently "has the mic" for TTS
	if not server_ref.can_bot_take_mic(bot_name):
		print("\t[%s bot] skipping AI check: someone else has the mic" % bot_name)
		pending_after_mic = true
		return

	# if I'm still in cooldown because I'm talking / just talked
	if voice_cooldown_timer > 0.0:
		print("\t[%s bot] skipping AI check: voice cooldown (AI is talking)" % bot_name)
		pending_after_voice = true
		return

	# spam guard between "should I reply?" checks
	if trigger_cooldown_timer > 0.0:
		print("\t[%s bot] skipping AI check: cooldown active" % bot_name)
		return

	_try_trigger_ai_check()


# server calls this when mic fully frees up
func on_mic_released() -> void:
	if pending_after_mic and not awaiting_ai:
		pending_after_mic = false
		if voice_cooldown_timer <= 0.0 and trigger_cooldown_timer <= 0.0:
			_try_trigger_ai_check()


# phase 1: cheap "should I reply?"
func _try_trigger_ai_check() -> void:
	var judge_ctx := _build_should_reply_context()

	awaiting_ai = true
	pending_mode = "should_reply"
	trigger_cooldown_timer = TRIGGER_COOLDOWN

	jllm_api.send_message(
		judge_ctx["system_prompt"],
		judge_ctx["messages"],
		50
	)


# phase 2: full reply text
func _request_final_reply() -> void:
	var reply_ctx := _build_reply_context()

	awaiting_ai = true
	pending_mode = "final_reply"

	jllm_api.send_message(
		reply_ctx["system_prompt"],
		reply_ctx["messages"],
		150
	)


# LLM callback
func _on_model_reply_ready(text: String) -> void:
	var result := _handle_model_reply(text)

	match result.get("action", ""):
		"generate":
			_request_final_reply()
		"speak":
			var said_text = result.get("text", "")
			server_ref.broadcast_ai_message(bot_name, said_text)
		"silence":
			pass
		_:
			pass


func _on_model_error(msg: String) -> void:
	print("\t[%s bot][AI error]: %s" % [bot_name, msg])
	awaiting_ai = false


# interpret LLM output based on which phase we're in
func _handle_model_reply(text: String) -> Dictionary:
	var cleaned := text.strip_edges()

	if pending_mode == "should_reply":
		awaiting_ai = false

		var answer := cleaned.to_lower()

		if answer.begins_with("yes"):
			# try to claim the "next turn"
			var got_slot := server_ref.reserve_generation(bot_name)

			if got_slot:
				print("\t[AI decision for %s] yes → generating reply" % bot_name)
				return {"action": "generate"}
			else:
				print("\t[AI decision for %s] yes → but lost turn, staying quiet" % bot_name)
				return {"action": "silence"}
		else:
			print("\t[AI decision for %s] no → stay quiet" % bot_name)
			return {"action": "silence"}


	if pending_mode == "final_reply":
		awaiting_ai = false

		var final_text := _postprocess_bot_speech(cleaned)

		# put it in chat history immediately
		chat_history.add_message("assistant", bot_name, final_text)

		# SUPER LOCKOUT:
		# temporarily set a big cooldown so I don't generate a 2nd message
		# before my first audio clip even starts playing.
		# AIChatServer will shrink this to the real clip length in notify_tts_started.
		voice_cooldown_timer = 9999.0
		pending_after_voice = false
		pending_after_mic = false

		return {
			"action": "speak",
			"text": final_text,
		}

	awaiting_ai = false
	return {"action": "none"}


# remove "Barack Obama:" / "As Barack Obama," etc
func _postprocess_bot_speech(raw_text: String) -> String:
	var t := raw_text.strip_edges()

	var prefixes := [
		"[" + bot_name + "]:",
		bot_name + ":",
		"[" + bot_name + "] :",
		bot_name + " :",
	]
	for p in prefixes:
		if t.begins_with(p):
			t = t.substr(p.length()).strip_edges()
			break

	var as_prefix := "As " + bot_name
	if t.begins_with(as_prefix):
		var comma_idx := t.find(",")
		if comma_idx != -1 and comma_idx < 40:
			t = t.substr(comma_idx + 1).strip_edges()

	return t


# context for phase 1
func _build_should_reply_context() -> Dictionary:
	var tail := chat_history.tail(DECISION_TAIL_LENGTH)

	var transcript := ""
	for e in tail:
		transcript += "%s: %s\n" % [e["name"], e["content"]]

	var system_prompt := """
You are %s in a fast multiplayer group chat.

Your job is to decide if YOU should speak RIGHT NOW in the chat.

Say "yes" if:
- Someone asked you a direct question (with or without your name).
- Someone asked for your judgment, approval, clarification, or leadership.
- You can add something relevant to the conversation
- Someone is talking about you, claiming you endorse something, or asking if you approve.
- The conversation is heated/confused and it's natural for you to step in.
- A new person is clearly confused and you'd realistically clarify.

Say "no" if:
- People are just chatting among themselves and don't need you.

Respond with exactly one word, lowercase:
yes
or
no
(no punctuation, no explanation)
""" % bot_name

	return {
		"system_prompt": system_prompt,
		"messages": [
			{
				"role": "user",
				"content": "Recent chat:\n" + transcript + "\nShould you reply now?"
			}
		]
	}


# context for phase 2
func _build_reply_context() -> Dictionary:
	var tail := chat_history.tail(REPLY_TAIL_LENGTH)

	var system_prompt := """
You are %s.

PERSONA RULES:
%s

CHAT RULES:
- Your chat display name is "%s".
- This is a fast group chat, casual and real-time.
- Keep replies short: 1-3 sentences max.
- Talk like a person, not like a narrator.
- Refer to people by name when you answer them.
- DO NOT introduce yourself. DO NOT start your reply with your own name, title, or role.
- DO NOT write lines like "%s:" or "[%s]:" or "As %s,".
Just speak normally.
Stay in character.
""" % [bot_name, persona_prompt, bot_name, bot_name, bot_name, bot_name]

	var chat_msgs: Array = []
	for e in tail:
		var line := "%s: %s" % [e["name"], e["content"]]
		if e["role"] == "assistant" and e["name"] == bot_name:
			chat_msgs.append({"role": "assistant", "content": line})
		else:
			chat_msgs.append({"role": "user", "content": line})

	return {
		"system_prompt": system_prompt,
		"messages": chat_msgs
	}
