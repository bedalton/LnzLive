extends Reference

# Columns are zero-based. IDs assigned by the section compiler are handled separately.
const BALL_COLUMNS = {
	"Add Ball": [0, 14],
	"Paint Ballz": [0],
	"Linez": [0, 1],
	"Polygons": [0, 1, 2, 3],
	"Move": [0, 4],
	"Project Ball": [0, 1],
	"Whiskers": [0, 1],
	"Eyes": [0, 1],
	"Omissions": [0],
	"No Texture Rotate": [0],
	"Ball Size Override": [0],
	"Fuzz Override": [0],
	"Add Ball Override": [0],
	"Color Info Override": [0],
	"Outline Color Override": [0]
}
const PALETTE_COLUMNS = {
	"Ballz Info": [0, 1, 2],
	"Add Ball": [4, 5, 6],
	"Paint Ballz": [5, 6],
	"Linez": [3, 4, 5],
	"Polygons": [4, 5, 6],
	"Color Info Override": [1],
	"Outline Color Override": [1],
	"256 Eyelid Color": [0]
}
const TEXTURE_COLUMNS = {
	"Ballz Info": [7],
	"Add Ball": [13],
	"Paint Ballz": [10],
	"Polygons": [8],
	"Color Info Override": [3]
}

var rows: Dictionary = {}
var texture_paths: Array = []
var _range_regex := RegEx.new()

func _init():
	_range_regex.compile("^([0-9]+)(?:\\s*-\\s*([0-9]+))?$")

# Keep ranges as intervals so a large input never allocates one entry per ID.
func parse_ranges(value: String, maximum: int = 2147483647):
	var intervals: Array = []
	if value.strip_edges().empty():
		return intervals
	for part in value.split(","):
		var result = _range_regex.search(part.strip_edges())
		if not result:
			return null
		var first = int(result.get_string(1))
		var last = int(result.get_string(2)) if not result.get_string(2).empty() else first
		if min(first, last) < 0 or max(first, last) > maximum:
			return null
		intervals.append([min(first, last), max(first, last)])
	return intervals

func scan(source: String, variation_config: Dictionary):
	var parser = LnzParser.new("")
	parser.scan_text(source)
	var source_lines = source.split("\n")
	rows.clear()
	texture_paths.clear()
	for section in parser.sections_map:
		if section != "Texture List" and not (BALL_COLUMNS.has(section) or PALETTE_COLUMNS.has(section) or TEXTURE_COLUMNS.has(section)):
			continue
		var section_rows: Array = []
		for line in parser.compile_source_lines(section, variation_config.get(section)):
			var content = source_lines[line].split(";", true, 1)[0].strip_edges()
			if content.empty() or content.begins_with("#"):
				continue
			var parts: Array = []
			if section == "Texture List":
				var path = parser.str_r.search(content)
				texture_paths.append(path.get_string())
			else:
				for token in parser.r.search_all(content):
					parts.append(token.get_string())
				if parts.empty():
					continue
			section_rows.append({"line": line, "parts": parts})
		rows[section] = section_rows

func matching_lines(ball_ranges: Array, palette_ranges: Array, texture_ranges: Array) -> Dictionary:
	var base_count = rows.get("Ballz Info", []).size()
	var attached = _attached_ball_ids(ball_ranges, base_count)
	var matches: Dictionary = {}
	for section in rows:
		var section_rows = rows[section]
		for index in range(section_rows.size()):
			if (section == "Eyes" and index >= 2) or (section == "256 Eyelid Color" and index >= 1):
				break
			var row = section_rows[index]
			var parts = row.parts
			if not ball_ranges.empty():
				var ball_match = (section == "Ballz Info" and _in_ranges(index, ball_ranges)) or (
					section == "Add Ball" and (_in_ranges(base_count + index, ball_ranges) or attached.has(base_count + index))
				)
				if not ball_match and not _matches_columns(parts, BALL_COLUMNS.get(section, []), ball_ranges, attached):
					continue
			if not palette_ranges.empty() and not _matches_columns(parts, PALETTE_COLUMNS.get(section, []), palette_ranges):
				continue
			if not texture_ranges.empty():
				var texture_match = _in_ranges(index, texture_ranges) if section == "Texture List" else (
					_matches_columns(parts, TEXTURE_COLUMNS.get(section, []), texture_ranges)
				)
				if not texture_match:
					continue
			matches[row.line] = true
	return matches

func _attached_ball_ids(ball_ranges: Array, base_count: int) -> Dictionary:
	var attached: Dictionary = {}
	if ball_ranges.empty():
		return attached
	var children: Dictionary = {}
	var queue: Array = []
	var addballs = rows.get("Add Ball", [])
	for index in range(addballs.size()):
		var parts = addballs[index].parts
		if not parts[0].is_valid_integer():
			continue
		var parent = int(parts[0])
		var child = base_count + index
		if not children.has(parent):
			children[parent] = []
		children[parent].append(child)
		if _in_ranges(parent, ball_ranges):
			attached[child] = true
			queue.append(child)
	while not queue.empty():
		for child in children.get(queue.pop_back(), []):
			if not attached.has(child):
				attached[child] = true
				queue.append(child)
	return attached

func _matches_columns(parts: Array, columns: Array, intervals: Array, attached: Dictionary = {}) -> bool:
	for column in columns:
		if column < parts.size() and parts[column].is_valid_integer():
			var value = int(parts[column])
			if attached.has(value) or _in_ranges(value, intervals):
				return true
	return false

func _in_ranges(value: int, intervals: Array) -> bool:
	for interval in intervals:
		if value >= interval[0] and value <= interval[1]:
			return true
	return false
