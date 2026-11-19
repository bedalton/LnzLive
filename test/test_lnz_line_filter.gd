extends GutTest

const LineFilter = preload("res://data_classes/lnz_line_filter.gd")

func test_ball_filter_follows_attachments_without_following_connections():
	var filter = LineFilter.new()
	filter.scan(PoolStringArray([
		"[Ballz Info]",
		"100 1 -1 0 -1 0 0 1",
		"200 1 -1 0 -1 0 0 2",
		"[Add Ball]",
		"0, 0.5, 0, 0, 100, 1, -1, 0, 0, -1, 0, 0, 0, 1",
		"2 0 0 0 102 1 -1 0 0 -1 0 0 0 2",
		"[Linez]",
		"3 1 0 100 1 1 100 100",
		"[Move]",
		"1 0 0 0",
		"1 0.5 0 0 3",
		"1 0 0 0 ; 0"
	]).join("\n"), {})
	var balls = filter.parse_ranges("0")
	assert_eq(filter.matching_lines(balls, [], []).keys(), [1, 4, 5, 7, 10])
	assert_eq(filter.matching_lines(balls, filter.parse_ranges("101-99", 255), filter.parse_ranges("1")).keys(), [1, 4])

func test_filter_uses_source_lines_in_compiled_variation_order():
	var source = PoolStringArray([
		"[Ballz Info]",
		"10 0 -1 0 -1 0 0 0",
		"#1.A First",
		"11 0 -1 0 -1 0 0 1",
		"#2.A Second",
		"12 0 -1 0 -1 0 0 1",
		"[Ballz Info]",
		"13 0 -1 0 -1 0 0 1",
		"[Texture List]",
		"base.bmp 0",
		"#1.A First",
		"first.bmp 0",
		"#2.A Second",
		"second.bmp 0"
	]).join("\n")
	var filter = LineFilter.new()
	filter.scan(source, {"Ballz Info": {0: "2.A"}, "Texture List": {0: "2.A"}})
	assert_eq(filter.texture_paths, ["base.bmp", "second.bmp"])
	assert_eq(filter.matching_lines(filter.parse_ranges("1-2"), [], []).keys(), [7, 5])
	assert_eq(filter.matching_lines([], filter.parse_ranges("12"), []).keys(), [5])
	assert_eq(filter.matching_lines([], [], filter.parse_ranges("1")).keys(), [7, 5, 13])

func test_filter_rejects_invalid_criteria_and_bounds_palette_indices():
	var filter = LineFilter.new()
	assert_eq(filter.parse_ranges("  "), [])
	assert_eq(filter.parse_ranges("1, 8 - 3"), [[1, 1], [3, 8]])
	assert_null(filter.parse_ranges("1, abc"))
	assert_null(filter.parse_ranges("-1"))
	assert_null(filter.parse_ranges("255-256", 255))
	assert_eq(filter.parse_ranges("0-2147483647"), [[0, 2147483647]])
