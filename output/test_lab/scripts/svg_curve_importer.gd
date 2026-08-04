class_name TestLabSvgCurveImporter
extends RefCounted

const NUMBER_PATTERN: String = "[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?"
const TOKEN_PATTERN: String = "[A-Za-z]|" + NUMBER_PATTERN


func parse(svg_source: String) -> Dictionary:
	var view_box := _parse_view_box(svg_source)
	if view_box.size.x <= 0.0 or view_box.size.y <= 0.0:
		return _error_result("SVG viewBox is missing or invalid.")
	var transform_result := _parse_group_transform(svg_source)
	if not bool(transform_result.get("ok", false)):
		return _error_result(String(transform_result.get("error", "Invalid transform.")))
	var svg_transform := transform_result.get("transform", Transform2D.IDENTITY) as Transform2D

	var path_regex := RegEx.new()
	if path_regex.compile("<path\\b[^>]*\\bd=\"([^\"]+)\"[^>]*/?>") != OK:
		return _error_result("Failed to compile SVG path matcher.")
	var curves: Array[Curve2D] = []
	var segment_counts: Array[int] = []
	for path_match in path_regex.search_all(svg_source):
		var path_result := _parse_path_data(path_match.get_string(1), svg_transform)
		if not bool(path_result.get("ok", false)):
			return _error_result(String(path_result.get("error", "Invalid SVG path.")))
		var path_curves: Array = path_result.get("curves", [])
		var path_segment_counts: Array = path_result.get("segment_counts", [])
		for curve_value: Variant in path_curves:
			curves.append(curve_value as Curve2D)
		for count_value: Variant in path_segment_counts:
			segment_counts.append(int(count_value))
	if curves.is_empty():
		return _error_result("SVG does not contain any supported closed path.")
	return {
		"ok": true,
		"error": "",
		"view_box": view_box,
		"curves": curves,
		"segment_counts": segment_counts,
	}


func _parse_view_box(svg_source: String) -> Rect2:
	var view_box_regex := RegEx.new()
	if view_box_regex.compile("viewBox\\s*=\\s*\"([^\"]+)\"") != OK:
		return Rect2()
	var view_box_match := view_box_regex.search(svg_source)
	if view_box_match == null:
		return Rect2()
	var values := _parse_numbers(view_box_match.get_string(1))
	if values.size() != 4:
		return Rect2()
	return Rect2(values[0], values[1], values[2], values[3])


func _parse_group_transform(svg_source: String) -> Dictionary:
	var group_regex := RegEx.new()
	if group_regex.compile("<g\\b[^>]*\\btransform=\"([^\"]+)\"") != OK:
		return {"ok": false, "error": "Failed to compile SVG transform matcher."}
	var group_match := group_regex.search(svg_source)
	if group_match == null:
		return {"ok": true, "transform": Transform2D.IDENTITY}

	var operation_regex := RegEx.new()
	if operation_regex.compile("([A-Za-z]+)\\s*\\(([^)]*)\\)") != OK:
		return {"ok": false, "error": "Failed to compile transform operation matcher."}
	var combined := Transform2D.IDENTITY
	for operation_match in operation_regex.search_all(group_match.get_string(1)):
		var operation_name := operation_match.get_string(1).to_lower()
		var values := _parse_numbers(operation_match.get_string(2))
		var operation := Transform2D.IDENTITY
		match operation_name:
			"translate":
				if values.is_empty() or values.size() > 2:
					return {"ok": false, "error": "Invalid translate() operation."}
				operation.origin = Vector2(values[0], values[1] if values.size() == 2 else 0.0)
			"scale":
				if values.is_empty() or values.size() > 2:
					return {"ok": false, "error": "Invalid scale() operation."}
				var scale_y: float = values[1] if values.size() == 2 else values[0]
				operation = Transform2D(
					Vector2(values[0], 0.0),
					Vector2(0.0, scale_y),
					Vector2.ZERO
				)
			"matrix":
				if values.size() != 6:
					return {"ok": false, "error": "Invalid matrix() operation."}
				operation = Transform2D(
					Vector2(values[0], values[1]),
					Vector2(values[2], values[3]),
					Vector2(values[4], values[5])
				)
			_:
				return {
					"ok": false,
					"error": "Unsupported SVG transform operation: %s." % operation_name,
				}
		combined = combined * operation
	return {"ok": true, "transform": combined}


func _parse_path_data(path_data: String, svg_transform: Transform2D) -> Dictionary:
	var token_regex := RegEx.new()
	if token_regex.compile(TOKEN_PATTERN) != OK:
		return {"ok": false, "error": "Failed to compile SVG path tokenizer."}
	var tokens: Array[String] = []
	for token_match in token_regex.search_all(path_data):
		tokens.append(token_match.get_string())

	var curves: Array[Curve2D] = []
	var segment_counts: Array[int] = []
	var active_curve: Curve2D
	var active_segments: int = 0
	var current := Vector2.ZERO
	var subpath_start := Vector2.ZERO
	var command := ""
	var token_index: int = 0
	while token_index < tokens.size():
		if _is_command_token(tokens[token_index]):
			command = tokens[token_index]
			token_index += 1
		if command.is_empty():
			return {"ok": false, "error": "SVG path data is missing a command."}
		match command:
			"M", "m":
				if token_index + 1 >= tokens.size():
					return {"ok": false, "error": "Move command is missing coordinates."}
				if active_curve != null and active_curve.point_count >= 2:
					curves.append(active_curve)
					segment_counts.append(active_segments)
				var move_target := Vector2(
					float(tokens[token_index]),
					float(tokens[token_index + 1])
				)
				token_index += 2
				current = current + move_target if command == "m" else move_target
				subpath_start = current
				active_curve = Curve2D.new()
				active_curve.add_point(svg_transform * current)
				active_segments = 0
				command = "l" if command == "m" else "L"
			"L", "l":
				if active_curve == null or token_index + 1 >= tokens.size():
					return {"ok": false, "error": "Line command is missing a current path."}
				var line_delta := Vector2(
					float(tokens[token_index]),
					float(tokens[token_index + 1])
				)
				token_index += 2
				var line_target: Vector2 = current + line_delta if command == "l" else line_delta
				active_curve.set_point_out(active_curve.point_count - 1, Vector2.ZERO)
				active_curve.add_point(svg_transform * line_target)
				current = line_target
				active_segments += 1
			"H", "h":
				if active_curve == null or token_index >= tokens.size():
					return {"ok": false, "error": "Horizontal line command is invalid."}
				var horizontal_value := float(tokens[token_index])
				token_index += 1
				var horizontal_target := Vector2(
					current.x + horizontal_value if command == "h" else horizontal_value,
					current.y
				)
				active_curve.set_point_out(active_curve.point_count - 1, Vector2.ZERO)
				active_curve.add_point(svg_transform * horizontal_target)
				current = horizontal_target
				active_segments += 1
			"V", "v":
				if active_curve == null or token_index >= tokens.size():
					return {"ok": false, "error": "Vertical line command is invalid."}
				var vertical_value := float(tokens[token_index])
				token_index += 1
				var vertical_target := Vector2(
					current.x,
					current.y + vertical_value if command == "v" else vertical_value
				)
				active_curve.set_point_out(active_curve.point_count - 1, Vector2.ZERO)
				active_curve.add_point(svg_transform * vertical_target)
				current = vertical_target
				active_segments += 1
			"C", "c":
				if active_curve == null or token_index + 5 >= tokens.size():
					return {"ok": false, "error": "Cubic command is missing coordinates."}
				var cubic_values: Array[float] = []
				for value_offset in range(6):
					cubic_values.append(float(tokens[token_index + value_offset]))
				token_index += 6
				var control_a := Vector2(cubic_values[0], cubic_values[1])
				var control_b := Vector2(cubic_values[2], cubic_values[3])
				var cubic_target := Vector2(cubic_values[4], cubic_values[5])
				if command == "c":
					control_a += current
					control_b += current
					cubic_target += current
				var transformed_current: Vector2 = svg_transform * current
				var transformed_control_a: Vector2 = svg_transform * control_a
				var transformed_control_b: Vector2 = svg_transform * control_b
				var transformed_target: Vector2 = svg_transform * cubic_target
				active_curve.set_point_out(
					active_curve.point_count - 1,
					transformed_control_a - transformed_current
				)
				active_curve.add_point(
					transformed_target,
					transformed_control_b - transformed_target
				)
				current = cubic_target
				active_segments += 1
			"Z", "z":
				if active_curve == null or active_curve.point_count < 2:
					return {"ok": false, "error": "Close command has no active path."}
				active_curve.set_point_out(active_curve.point_count - 1, Vector2.ZERO)
				active_curve.add_point(svg_transform * subpath_start)
				active_segments += 1
				curves.append(active_curve)
				segment_counts.append(active_segments)
				active_curve = null
				active_segments = 0
				current = subpath_start
				command = ""
			_:
				return {"ok": false, "error": "Unsupported SVG path command: %s." % command}
	if active_curve != null and active_curve.point_count >= 2:
		curves.append(active_curve)
		segment_counts.append(active_segments)
	return {
		"ok": true,
		"curves": curves,
		"segment_counts": segment_counts,
	}


func _parse_numbers(source: String) -> Array[float]:
	var number_regex := RegEx.new()
	if number_regex.compile(NUMBER_PATTERN) != OK:
		return []
	var values: Array[float] = []
	for number_match in number_regex.search_all(source):
		values.append(float(number_match.get_string()))
	return values


func _is_command_token(token: String) -> bool:
	return token.length() == 1 and token.to_lower() != token.to_upper()


func _error_result(message: String) -> Dictionary:
	return {"ok": false, "error": message, "curves": [], "segment_counts": []}
