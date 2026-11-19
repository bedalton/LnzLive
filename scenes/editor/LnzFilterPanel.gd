extends PanelContainer

const LineFilter = preload("res://data_classes/lnz_line_filter.gd")

onready var editor: TextEdit = get_node("../LnzTextEdit")
onready var fields = [$Controls/Balls, $Controls/Palette, $Controls/Texture/Tokens]
onready var slots: OptionButton = $Controls/Texture/Slots
onready var status: Label = $Controls/Status

var active: bool = false
var _filter = LineFilter.new()
var _criteria: Array = [[], [], []]
var _matches: Dictionary = {}
var _expanded: Dictionary = {}
var _hidden: Dictionary = {}
var _pinned_line: int = -1
var _line_count: int = 0
var _refresh_queued: bool = false
var _pin_edit: bool = false
var _force_refresh: bool = false
var _pending_edit_line: int = -1
var _drag_selection: bool = false

func _ready():
	get_node("../HBoxContainer/FilterButton").connect("pressed", self, "_toggle")
	$Controls/Actions/Apply.connect("pressed", self, "_apply")
	$Controls/Actions/Clear.connect("pressed", self, "clear")
	$Controls/Actions/Close.connect("pressed", self, "hide")
	$Controls/Actions/Selection.connect("pressed", self, "_use_selected_balls")
	var menu_style = preload("res://resources/styles/styleboxflat_button_normal.tres")
	slots.get_popup().add_stylebox_override("panel", menu_style)
	slots.get_popup().add_font_override("font", slots.get_font("font"))
	slots.connect("item_selected", self, "_pick_slot")
	for field in fields:
		field.connect("text_entered", self, "_apply")

func _toggle():
	if visible:
		hide()
		return
	editor._on_FindCloseButton_pressed()
	show()
	if not active:
		_scan()
	fields[0].grab_focus()

func _apply(_submitted_text: String = ""):
	var criteria: Array = []
	for index in range(fields.size()):
		var maximum = 255 if index == 1 else 2147483647
		var intervals = _filter.parse_ranges(fields[index].text, maximum)
		if intervals == null:
			status.text = "Enter comma-separated IDs or ranges, such as 1, 4-7."
			if index == 1:
				status.text = "Palette indices must be between 0 and 255."
			fields[index].grab_focus()
			return
		criteria.append(intervals)

	if criteria == [[], [], []]:
		clear()
		return
	if not active:
		editor.set_hiding_enabled(true)
		if editor.has_method("is_drag_and_drop_selection_enabled"):
			_drag_selection = editor.is_drag_and_drop_selection_enabled()
			editor.set_drag_and_drop_selection_enabled(false)
	active = true
	_criteria = criteria
	_expanded.clear()
	_pinned_line = -1
	editor.deselect()
	_refresh()
	editor.grab_focus()

func clear():
	if active:
		editor.set_hiding_enabled(false)
		if editor.has_method("set_drag_and_drop_selection_enabled"):
			editor.set_drag_and_drop_selection_enabled(_drag_selection)
	active = false
	_matches.clear()
	_hidden.clear()
	_expanded.clear()
	_pinned_line = -1
	_pin_edit = false
	_force_refresh = false
	_pending_edit_line = -1
	for field in fields:
		field.clear()
	status.text = ""

func filter_ball(ball_no: int):
	editor._on_FindCloseButton_pressed()
	show()
	fields[0].text = str(ball_no)
	fields[1].clear()
	fields[2].clear()
	_apply()

func _use_selected_balls():
	var ids = PoolStringArray()
	for ball in editor.pet_view.selected_balls:
		if is_instance_valid(ball):
			ids.append(str(ball.ball_no))
	if ids.empty() and is_instance_valid(editor.pet_view.active_selected_ball):
		ids.append(str(editor.pet_view.active_selected_ball.ball_no))
	if ids.empty():
		status.text = "Select a ball in the viewport first."
	else:
		fields[0].text = ids.join(", ")

func _pick_slot(index: int):
	if index > 0:
		fields[2].text = str(slots.get_item_id(index))
		slots.select(0)

func _scan():
	var previous_paths = _filter.texture_paths.duplicate()
	_filter.scan(editor.text, editor.pet_node.current_variation_config)
	if slots.get_item_count() > 0 and previous_paths == _filter.texture_paths:
		return
	slots.clear()
	slots.add_item("Texture slots")
	for index in range(_filter.texture_paths.size()):
		slots.add_item("%d  %s" % [index, _filter.texture_paths[index]], index)
	slots.disabled = slots.get_item_count() == 1

func queue_refresh(pin_edit: bool = false):
	if not active and not visible:
		return
	_pin_edit = _pin_edit or pin_edit
	_force_refresh = _force_refresh or not pin_edit
	if not _refresh_queued:
		_refresh_queued = true
		call_deferred("_refresh_after_change")

func _refresh_after_change():
	_refresh_queued = false
	var pin_edit = _pin_edit
	var force_refresh = _force_refresh
	_pin_edit = false
	_force_refresh = false
	var caret = editor.cursor_get_line()
	# An incomplete row can change which other rows match. Keep the current
	# visibility until the caret leaves, so those rows cannot move the viewport.
	if active and pin_edit and not force_refresh and editor.has_focus() and (
		_line_count == editor.get_line_count() and not editor.is_line_hidden(caret)
	):
		_pending_edit_line = caret
		return
	_refresh(pin_edit)

func _refresh(pin_edit: bool = false):
	_pending_edit_line = -1
	if not active and not visible:
		return
	_scan()
	if not active:
		return

	if _line_count != editor.get_line_count():
		_expanded.clear()
		_hidden.clear()
	_line_count = editor.get_line_count()
	_matches = _filter.matching_lines(_criteria[0], _criteria[1], _criteria[2])
	var caret = editor.cursor_get_line()
	if pin_edit and not _matches.has(caret):
		_pinned_line = caret
	status.text = "%d matching lines" % _matches.size() if not _matches.empty() else "No matching lines"
	_update_visibility()

func caret_changed():
	if not active:
		return
	var caret = editor.cursor_get_line()
	if _pinned_line != -1 and caret != _pinned_line:
		_pinned_line = -1
		if _pending_edit_line == -1:
			_update_visibility()
	if _pending_edit_line != -1 and caret != _pending_edit_line:
		_refresh()

func capture_expansion():
	if not active:
		return
	# The TextEdit fold gutter unhides the contiguous gap below the clicked line.
	for line in _hidden.keys():
		if line < editor.get_line_count() and not editor.is_line_hidden(line):
			_expanded[line] = true
	_update_visibility()

func _update_visibility():
	var caret = editor.cursor_get_line()
	var nearest = 0
	_hidden.clear()
	for line in range(editor.get_line_count()):
		var content = editor.get_line(line).strip_edges()
		# The first line anchors the gutter when a hidden gap precedes the first section.
		var hidden = line != 0 and line != _pinned_line and not (
			_matches.has(line) or _expanded.has(line) or content.begins_with("[") or content.begins_with("#")
		)
		if hidden:
			_hidden[line] = true
		elif abs(line - caret) < abs(nearest - caret):
			nearest = line
		if editor.is_line_hidden(line) != hidden:
			editor.set_line_as_hidden(line, hidden)
	if _hidden.has(caret):
		editor.cursor_set_line(nearest)
		editor.center_viewport_to_cursor()
