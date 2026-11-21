extends PanelContainer

const LineFilter = preload("res://data_classes/lnz_line_filter.gd")

onready var editor: TextEdit = get_node("../LnzTextEdit")
onready var fields = [$Controls/Balls, $Controls/Palette, $Controls/Texture/Tokens]
onready var inherited_values: CheckBox = $Controls/InheritedValues
onready var slots: OptionButton = $Controls/Texture/Slots
onready var status: Label = $Controls/Status

var active: bool = false
var _filter = LineFilter.new()
var _criteria: Array = [[], [], []]
var _include_inherited: bool = false
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
var _backspace_scroll: float = -1.0
var _pending_scroll: float = -1.0
var _clamped_scroll: float = 0.0

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
	_include_inherited = inherited_values.pressed
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
	_backspace_scroll = -1.0
	_pending_scroll = -1.0
	for field in fields:
		field.clear()
	inherited_values.pressed = false
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
	_matches = _filter.matching_lines(_criteria[0], _criteria[1], _criteria[2], _include_inherited)
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

func prepare_backspace():
	_backspace_scroll = editor.get_v_scroll()

func restore_gap_before_caret():
	# TextEdit unfolds the preceding gap before deleting a character and can
	# scroll to keep the caret visible in that temporarily expanded view.
	var scroll = _backspace_scroll
	_backspace_scroll = -1.0
	var line = editor.cursor_get_line() - 1
	if not _hidden.has(line) or editor.is_line_hidden(line):
		return
	while _hidden.has(line) and not editor.is_line_hidden(line):
		editor.set_line_as_hidden(line, true)
		line -= 1
	if scroll >= 0.0:
		_set_filtered_scroll(scroll)
		editor.cursor_set_column(editor.cursor_get_column())

func capture_expansion():
	if not active:
		return
	# The TextEdit fold gutter unhides the contiguous gap below the clicked line.
	for line in _hidden.keys():
		if line < editor.get_line_count() and not editor.is_line_hidden(line):
			_expanded[line] = true
	_update_visibility()

func _update_visibility():
	_pending_scroll = -1.0
	var caret = editor.cursor_get_line()
	var nearest = 0
	var scroll = editor.get_v_scroll()
	var top_margin = editor.get_stylebox("normal").get_margin(MARGIN_TOP)
	var top_line = int(editor.get_line_column_at_pos(Vector2(0, ceil(top_margin))).y)
	var rows_above_top = 0
	var visibility_changed = false
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
			visibility_changed = true
			if line < top_line:
				var rows = 1 + editor.get_line_wrap_count(line)
				rows_above_top += -rows if hidden else rows
			editor.set_line_as_hidden(line, hidden)
	if _hidden.has(caret):
		editor.cursor_set_line(nearest)
		editor.center_viewport_to_cursor()
	elif visibility_changed:
		var target_scroll = scroll + rows_above_top
		if _hidden.has(top_line):
			# A hidden top line has no wrapped rows left to anchor.
			target_scroll = _visible_rows_before(top_line) + fposmod(scroll, 1.0)
		target_scroll = clamp(target_scroll, 0.0, max(0, editor.get_total_visible_rows() - editor.get_visible_rows()))
		_set_filtered_scroll(target_scroll)
		if target_scroll > editor.get_v_scroll():
			# Newly revealed rows extend the scrollbar range on the next draw.
			_pending_scroll = target_scroll
			_clamped_scroll = editor.get_v_scroll()
			if not editor.is_connected("draw", self, "_restore_scroll_after_draw"):
				editor.connect("draw", self, "_restore_scroll_after_draw", [], CONNECT_ONESHOT | CONNECT_DEFERRED)

func _visible_rows_before(line: int) -> int:
	var rows = 0
	for index in range(line):
		if not editor.is_line_hidden(index):
			rows += 1 + editor.get_line_wrap_count(index)
	return rows

func _set_filtered_scroll(scroll: float):
	editor.set_v_scroll(scroll)
	# Godot 3 only remaps the first visible line on a scrollbar value change.
	# Hiding rows can change that mapping even when the value stays the same.
	editor._scroll_moved(editor.get_v_scroll())

func _restore_scroll_after_draw():
	var scroll = _pending_scroll
	_pending_scroll = -1.0
	if active and scroll >= 0.0 and is_equal_approx(editor.get_v_scroll(), _clamped_scroll):
		_set_filtered_scroll(scroll)
