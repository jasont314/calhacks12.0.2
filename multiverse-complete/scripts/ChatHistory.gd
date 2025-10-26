extends Node
class_name ChatHistory

const MAX_CONTEXT_MESSAGES := 60

var history: Array = []
# each item:
# {
#   "role": "user" | "assistant",
#   "name": "Player2" | "Barack Obama" | etc,
#   "content": "text",
#   "timestamp": unix_time
# }

func add_message(role: String, speaker_name: String, content: String) -> void:
	history.append({
		"role": role,
		"name": speaker_name,
		"content": content,
		"timestamp": Time.get_unix_time_from_system(),
	})
	_trim()

func _trim() -> void:
	if history.size() > MAX_CONTEXT_MESSAGES:
		history = history.slice(-MAX_CONTEXT_MESSAGES)

func tail(n: int) -> Array:
	if history.size() <= n:
		return history.duplicate()
	return history.slice(history.size() - n, history.size())
