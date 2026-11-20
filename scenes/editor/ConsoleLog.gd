extends RichTextLabel
## ConsoleLog.gd
## Displays a rolling log of messages with fade-out effects

export var max_messages: int = 5
export var display_time: float = 3.0
export var fade_speed: float = 1.5

var current_messages: Array = []

func _ready() -> void:
	bbcode_enabled = true
	scroll_active = false
	log_message("Welcome to LnzLive...")

func log_message(msg: String) -> void:
	_add_message(msg, false)

func log_warning(msg: String) -> void:
	for i in range(current_messages.size() - 1, -1, -1):
		if current_messages[i]["warning"]:
			current_messages.remove(i)
			break
	_add_message(msg, true)

func _add_message(msg: String, warning: bool) -> void:
	var entry: Dictionary = {
		"text": msg,
		"warning": warning,
		"alpha": 1.0,
		"timer": display_time
	}
	current_messages.append(entry)
	
	if current_messages.size() > max_messages:
		current_messages.pop_front()
	
	_update_display()

func _process(delta: float) -> void:
	if current_messages.empty():
		return

	var needs_update: bool = false
	var i: int = current_messages.size() - 1
	
	while i >= 0:
		var msg: Dictionary = current_messages[i]
		msg["timer"] -= delta
		
		if msg["timer"] <= 1.0:
			msg["alpha"] = max(0.0, msg["timer"])
			needs_update = true
		
		if msg["timer"] <= 0:
			current_messages.remove(i)
			needs_update = true
		
		i -= 1

	if needs_update:
		_update_display()

func _update_display() -> void:
	clear()
	# Keep warnings visible when status messages fill the log.
	for msg in current_messages:
		if msg["warning"]:
			_append_message(msg, Color(1.0, 0.75, 0.35))
			break
	for msg in current_messages:
		if not msg["warning"]:
			_append_message(msg, Color.white)

func _append_message(msg: Dictionary, color: Color) -> void:
	color.a = msg["alpha"]
	push_color(color)
	append_bbcode(msg["text"] + "\n")
	pop()
