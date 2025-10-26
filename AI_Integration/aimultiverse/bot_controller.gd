extends Node
class_name BotController

# injected by server
var server_ref: TestAIChatServer
var chat_history: ChatHistory
var jllm_api: JLLMApi
var bot_name: String = ""
var persona_prompt: String = ""

# state
var awaiting_ai := false
var pending_mode := ""            # "should_reply" | "final_reply"

var pending_after_voice := false  # "I wanted to talk but I was still in my own VOICE_COOLDOWN"
var pending_after_mic := false    # "I wanted to talk but another bot held the mic"

var voice_cooldown_timer := 0.0
var trigger_cooldown_timer := 0.0

const VOICE_COOLDOWN := 0.0
const TRIGGER_COOLDOWN := 1.0
const DECISION_TAIL_LENGTH := 6
const REPLY_TAIL_LENGTH := 12

# who last spoke
var last_speaker_name := ""
var last_speaker_is_bot := false


func _ready() -> void:
	set_process(true)
	jllm_api.reply_ready.connect(_on_model_reply_ready)
	jllm_api.api_error.connect(_on_model_error)


func _process(delta: float) -> void:
	# tick down our "I'm still talking" cooldown
	if voice_cooldown_timer > 0.0:
		voice_cooldown_timer -= delta
		if voice_cooldown_timer <= 0.0 and pending_after_voice:
			# we were waiting for our own voice cooldown to end
			pending_after_voice = false
			_try_trigger_ai_check()

	# tick down spam cooldown
	if trigger_cooldown_timer > 0.0:
		trigger_cooldown_timer -= delta


#
# NEW: server calls this after mic fully releases.
# If we had wanted to talk but got blocked by mic lock,
# try now.
#
func on_mic_released() -> void:
	if pending_after_mic:
		pending_after_mic = false
		_try_trigger_ai_check()


#
# Called by server whenever ANYONE talks (player OR another bot).
#
func on_player_message(speaker_name: String, text: String) -> void:
	last_speaker_name = speaker_name
	last_speaker_is_bot = _is_other_bot(speaker_name)

	# already waiting on a model response? can't stack
	if awaiting_ai:
		_log_bot("[%s bot] skipping AI check: already waiting on model" % bot_name)
		return

	# MIC RULE:
	# normally, respect mic lock (other bot is "holding the floor")
	var can_take_mic_now := server_ref.can_bot_take_mic(bot_name)
	var mic_blocked := (not can_take_mic_now)

	# we allow rude interrupt ONLY if last speaker was another bot (trash talk feeling),
	# BUT if you don't want that behavior anymore, comment this next line out.
	if last_speaker_is_bot and last_speaker_name != bot_name:
		mic_blocked = false

	if mic_blocked:
		# can't talk yet; remember we want to jump in once mic frees
		_log_bot("[%s bot] mic busy, will retry after release" % bot_name)
		pending_after_mic = true
		return

	# if we're still in our own voice cooldown, wait and retry later
	if voice_cooldown_timer > 0.0:
		_log_bot("[%s bot] skipping AI check: voice cooldown active (AI is talking)" % bot_name)
		pending_after_voice = true
		return

	# anti-spam
	if trigger_cooldown_timer > 0.0:
		_log_bot("[%s bot] skipping AI check: cooldown active" % bot_name)
		return

	_try_trigger_ai_check()


#
# Phase 1: model "should I reply?"
#
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


#
# Phase 2: model "give me the reply text"
#
func _request_final_reply() -> void:
	var reply_ctx := _build_reply_context()

	awaiting_ai = true
	pending_mode = "final_reply"

	jllm_api.send_message(
		reply_ctx["system_prompt"],
		reply_ctx["messages"],
		150
	)


#
# MODEL CALLBACKS
#
func _on_model_reply_ready(text: String) -> void:
	var result := _handle_model_reply(text)

	match result.get("action", ""):
		"generate":
			_request_final_reply()

		"speak":
			var said_text = result.get("text", "")
			var speaker = result.get("bot_name", bot_name)
			server_ref.broadcast_ai_message(speaker, said_text)

		"silence":
			pass

		_:
			pass


func _on_model_error(msg: String) -> void:
	_log_bot("[%s bot][AI error]: %s" % [bot_name, msg])
	awaiting_ai = false


#
# INTERNAL: handle phase results
#
func _handle_model_reply(text: String) -> Dictionary:
	var cleaned := text.strip_edges()

	if pending_mode == "should_reply":
		awaiting_ai = false

		var answer := cleaned.to_lower()
		var model_thinks_yes := answer.begins_with("yes")

		# override: if last speaker was a different bot, force yes
		if last_speaker_is_bot and last_speaker_name != bot_name:
			model_thinks_yes = true

		if model_thinks_yes:
			_log_bot("[AI decision for %s] yes → generating reply" % bot_name)
			return {"action": "generate"}
		else:
			_log_bot("[AI decision for %s] no → stay quiet" % bot_name)
			return {"action": "silence"}

	if pending_mode == "final_reply":
		awaiting_ai = false

		var final_text := _postprocess_bot_speech(cleaned)

		# claim mic and log in shared history
		server_ref.claim_mic_for_bot(bot_name)
		chat_history.add_message("assistant", bot_name, final_text)

		# now that we successfully spoke, clear any "i was waiting"
		pending_after_mic = false
		pending_after_voice = false

		# start our self-cooldown (tts time)
		voice_cooldown_timer = VOICE_COOLDOWN

		return {
			"action": "speak",
			"text": final_text,
			"bot_name": bot_name,
		}

	# fallback
	awaiting_ai = false
	return {"action": "none"}


#
# Remove leading speaker tags from model output
#
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


#
# Build context for PHASE 1
#
func _build_should_reply_context() -> Dictionary:
	var tail := chat_history.tail(DECISION_TAIL_LENGTH)

	var transcript := ""
	for e in tail:
		transcript += "%s: %s\n" % [e["name"], e["content"]]

	var clash_rules := ""
	if last_speaker_is_bot and last_speaker_name != bot_name:
		clash_rules = """
SPECIAL RULE FOR THIS MOMENT:
- The last message came from another high-profile figure (%s).
- If they challenged you, disagreed with you, talked about you, or tried to assert dominance,
  you SHOULD answer right now, even if it would normally be polite to wait.
- In that case you will answer immediately. Output "yes".
""" % last_speaker_name

	var system_prompt := """
You are %s in a fast multiplayer group chat.

Your job is to decide if YOU should speak RIGHT NOW in the chat.

Say "yes" ONLY if:
- Someone asked you a direct question (with or without your name).
- Someone asked for your judgment, approval, clarification, or leadership.
- Someone is talking about you, claiming you endorse something, or asking if you approve.
- The conversation is heated/confused and it's natural for you to step in.
- A new person is clearly confused and you'd realistically clarify.
- Another public figure in the chat is challenging you or trying to speak for you.

Say "no" if:
- People are just chatting among themselves and don't need you.
- It would feel like interrupting for no good reason.
- Your input wouldn't help right now.

%s

You MUST respond with exactly one word, lowercase:
yes
or
no
(no punctuation, no explanation)
""" % [bot_name, clash_rules]

	return {
		"system_prompt": system_prompt,
		"messages": [
			{
				"role": "user",
				"content": "Recent chat:\n" + transcript + "\nShould you reply now?"
			}
		]
	}


#
# Build context for PHASE 2
#
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
			chat_msgs.append({
				"role": "assistant",
				"content": line
			})
		else:
			chat_msgs.append({
				"role": "user",
				"content": line
			})

	return {
		"system_prompt": system_prompt,
		"messages": chat_msgs
	}


func _is_other_bot(name_to_check: String) -> bool:
	if server_ref == null:
		return false
	for b in server_ref.bots:
		if b.bot_name == name_to_check and b.bot_name != bot_name:
			return true
	return false


func _log_bot(msg: String) -> void:
	if server_ref != null:
		var t := server_ref._now_s()
		print("\t[%0.2fs] %s" % [t, msg])
	else:
		print("\t[??] %s" % msg)
