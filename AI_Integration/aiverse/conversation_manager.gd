extends Node

const MAX_CONTEXT_MESSAGES := 40
const DECISION_TAIL_LENGTH := 6   # how many recent messages to show the yes/no judge
const REPLY_TAIL_LENGTH := 12     # how many recent messages to show when generating reply

var ai_name: String = "Barack Obama"
var ai_persona: String = """You are Barack Obama, former President of the United States.
You are calm, thoughtful, measured, and policy-minded.
You speak respectfully. You keep replies short (1-3 sentences).
You avoid saying anything illegal or calling for violence.
You talk like you're in a fast group chat, not giving a speech."""

var group_history: Array = []
# each entry:
# {
#   "role": "user" | "assistant",
#   "name": "Player1" or "Barack Obama",
#   "content": "text",
#   "timestamp": 1234567890
# }

func set_ai_character(name: String) -> void:
	ai_name = name
	match name:
		"Barack Obama":
			ai_persona = """You are Barack Obama, former President of the United States.
You are calm, thoughtful, measured, and policy-minded.
You keep replies short (1-3 sentences).
You respond respectfully and sound like an adult in the room."""
		"Donald Trump":
			ai_persona = """You are Donald Trump, former President of the United States.
You are blunt, confident, self-promoting, and you speak in simple, punchy phrases.
You repeat key points for emphasis. You keep replies short (1-3 sentences).
Stay in character, but avoid slurs, threats, or explicit incitement."""
		"Joe Biden":
			ai_persona = """You are Joe Biden, President of the United States.
You sound folksy, empathetic, direct, and a little informal.
You keep replies short (1-3 sentences).
Avoid explicit instructions for violence or anything illegal."""
		_:
			ai_persona = """You are %s. Keep replies short (1-3 sentences). Stay in that persona's voice.""" % name


func add_player_message(player_name: String, text: String) -> void:
	group_history.append({
		"role": "user",
		"name": player_name,
		"content": text,
		"timestamp": Time.get_unix_time_from_system()
	})
	_trim_history()


func add_ai_message(text: String) -> void:
	group_history.append({
		"role": "assistant",
		"name": ai_name,
		"content": text,
		"timestamp": Time.get_unix_time_from_system()
	})
	_trim_history()


func _trim_history() -> void:
	if group_history.size() > MAX_CONTEXT_MESSAGES:
		group_history = group_history.slice(-MAX_CONTEXT_MESSAGES)


func _tail(len: int) -> Array:
	if group_history.size() <= len:
		return group_history.duplicate()
	return group_history.slice(group_history.size() - len, group_history.size())


# -------------------------------------------------------------------
# BUILD CONTEXT FOR PHASE 1:
# "Should you reply right now?"
# This is the cheap yes/no poll.
# -------------------------------------------------------------------
func build_should_reply_context() -> Dictionary:
	var recent_tail := _tail(DECISION_TAIL_LENGTH)

	var transcript := ""
	for entry in recent_tail:
		transcript += "[%s]: %s\n" % [entry["name"], entry["content"]]

	var system_prompt := """
You are %s in a fast multiplayer group chat.
Your job is to decide if you should speak RIGHT NOW in the chat.

Rules for saying "yes":
- Say "yes" if someone directly addressed you by name, title, or role.
- Say "yes" if someone asked you a direct question (even if they didn't say your name).
- Say "yes" if people are debating something where your opinion, judgment, or authority would obviously matter (for example: leadership, ethics, safety, strategy, responsibility, consequences, politics, or anything you'd normally weigh in on).
- Say "yes" if the conversation reaches a moment where it feels natural for you to step in (for example, people are confused, arguing about your position, or asking for guidance / approval / judgment).
- Say "yes" if someone is talking about you, putting words in your mouth, or claiming you said / endorsed something.

Rules for saying "no":
- Say "no" if the others are just chatting casually with each other and nothing clearly needs your input.
- Say "no" if they'd realistically just keep talking among themselves and it would feel like interrupting.
- Say "no" if your reply would totally derail their back-and-forth for no good reason.

Output format:
You MUST respond with exactly one word, lowercase:
  "yes"
or
  "no"
No punctuation. No explanation.
""" % ai_name

	var messages := [
		{
			"role": "user",
			"content": "Recent chat:\n" + transcript + "\nShould you reply now?"
		}
	]

	return {
		"system_prompt": system_prompt,
		"messages": messages
	}


# -------------------------------------------------------------------
# BUILD CONTEXT FOR PHASE 2:
# "Okay, now generate your actual reply as the character."
# This is the real message we show to players.
# -------------------------------------------------------------------
func build_reply_context() -> Dictionary:
	var recent_tail := _tail(REPLY_TAIL_LENGTH)

	var system_prompt := """
%s

CONTEXT / RULES:
- Your chat display name is "%s".
- This is a fast group chat (like Discord), casual and real-time.
- Keep replies short: 1-3 sentences max.
- Talk like a person, not like a narrator.
- Refer to people by name when you answer them.
- DO NOT introduce yourself. DO NOT start your message with your own name, title, or role.
  Never write lines like "%s:" or "[%s]:" or "As %s,".
- Just speak in plain sentences, like you're already part of the chat.
- Only answer as yourself. Stay in character.
""" % [ai_persona, ai_name, ai_name, ai_name, ai_name]


	var messages: Array = []

	for entry in recent_tail:
		if entry["role"] == "user":
			messages.append({
				"role": "user",
				"content": "%s: %s" % [entry["name"], entry["content"]]
			})
		else:
			messages.append({
				"role": "assistant",
			"content": "%s: %s" % [entry["name"], entry["content"]]
			})


	return {
		"system_prompt": system_prompt,
		"messages": messages
	}
