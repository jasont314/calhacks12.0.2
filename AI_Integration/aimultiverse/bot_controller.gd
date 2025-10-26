extends Node
class_name BotController

var server_ref: TestAIChatServer
var chat_history: ChatHistory
var jllm_api: JLLMApi
var bot_name: String = ""
var persona_prompt: String = ""

var awaiting_ai := false
var pending_mode := ""               # "should_reply" | "final_reply"
var pending_after_voice := false     # we tried to talk but we were still 'talking'
var pending_after_mic := false       # we tried to talk but someone else had the mic

var voice_cooldown_timer := 0.0
var trigger_cooldown_timer := 0.0

const VOICE_COOLDOWN := 1.5
const TRIGGER_COOLDOWN := 1.0
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


# Called by the server whenever ANYONE (player or bot) says something.
func on_player_message(_speaker_name: String, _text: String) -> void:
	if awaiting_ai:
		print("\t[%s bot] skipping AI check: already waiting on model" % bot_name)
		return

	# check turn-taking with server (mic or pre-reservation)
	if not server_ref.can_bot_take_mic(bot_name):
		print("\t[%s bot] skipping AI check: someone else has the mic" % bot_name)
		pending_after_mic = true
		return

	if voice_cooldown_timer > 0.0:
		print("\t[%s bot] skipping AI check: voice cooldown (AI is talking)" % bot_name)
		pending_after_voice = true
		return

	if trigger_cooldown_timer > 0.0:
		print("\t[%s bot] skipping AI check: cooldown active" % bot_name)
		return

	_try_trigger_ai_check()


# Server calls this when the mic is released so bots that were blocked can try again.
func on_mic_released() -> void:
	if pending_after_mic and not awaiting_ai:
		pending_after_mic = false
		if voice_cooldown_timer <= 0.0 and trigger_cooldown_timer <= 0.0:
			_try_trigger_ai_check()


# ---- Phase 1: should I reply? ----
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


# ---- Phase 2: generate reply ----
func _request_final_reply() -> void:
	var reply_ctx := _build_reply_context()

	awaiting_ai = true
	pending_mode = "final_reply"

	jllm_api.send_message(
		reply_ctx["system_prompt"],
		reply_ctx["messages"],
		150
	)


# ---- MODEL CALLBACKS ----
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


# ---- Interpret model output ----
func _handle_model_reply(text: String) -> Dictionary:
	var cleaned := text.strip_edges()

	if pending_mode == "should_reply":
		awaiting_ai = false

		var answer := cleaned.to_lower()

		if answer.begins_with("yes"):
			# Try to reserve the "next turn" immediately.
			var got_slot := server_ref.reserve_generation(bot_name)

			if got_slot:
				print("\t[AI decision for %s] yes → generating reply" % bot_name)
				return {"action": "generate"}
			else:
				# We wanted to speak, but someone else already reserved this turn.
				print("\t[AI decision for %s] yes → but lost turn, staying quiet" % bot_name)
				return {"action": "silence"}
		else:
			print("\t[AI decision for %s] no → stay quiet" % bot_name)
			return {"action": "silence"}

	if pending_mode == "final_reply":
		awaiting_ai = false

		var final_text := _postprocess_bot_speech(cleaned)

		# record it and start local cooldown
		chat_history.add_message("assistant", bot_name, final_text)
		voice_cooldown_timer = VOICE_COOLDOWN
		pending_after_voice = false
		pending_after_mic = false

		return {
			"action": "speak",
			"text": final_text,
		}

	awaiting_ai = false
	return {"action": "none"}


# ---- Output cleanup ----
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


# ---- Prompt builders ----
func _build_should_reply_context() -> Dictionary:
	var tail := chat_history.tail(DECISION_TAIL_LENGTH)
	var transcript := ""
	for e in tail:
		transcript += "%s: %s\n" % [e["name"], e["content"]]

	var system_prompt := """
You are %s in a fast multiplayer group chat.

Your job is to decide if YOU should speak RIGHT NOW in the chat.

Say "yes" ONLY if:
- Someone asked you a direct question (with or without your name).
- Someone asked for your judgment, approval, clarification, or leadership.
- Someone is talking about you, claiming you endorse something, or asking if you approve.
- The conversation is heated/confused and it's natural for you to step in.
- A new person is clearly confused and you'd realistically clarify.

Say "no" if:
- People are just chatting among themselves and don't need you.
- It would feel like interrupting for no good reason.
- Your input wouldn't actually help move things forward right now.

Respond with exactly one word, lowercase:
yes
or
no
(no punctuation, no explanation)
""" % bot_name

	return {
		"system_prompt": system_prompt,
		"messages": [
			{ "role": "user", "content": "Recent chat:\n" + transcript + "\nShould you reply now?" }
		]
	}


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
			chat_msgs.append({ "role": "assistant", "content": line })
		else:
			chat_msgs.append({ "role": "user", "content": line })

	return {
		"system_prompt": system_prompt,
		"messages": chat_msgs
	}
