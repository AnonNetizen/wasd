class_name PolygonAssetCompilerCore
extends RefCounted

const SUPPORTED_MANIFEST_SCHEMA: int = 1
const SUPPORTED_STYLE_SCHEMA: int = 1


func compile_manifest(manifest_path: String) -> Dictionary:
	var manifest_result := _load_json_dictionary(manifest_path)
	if not manifest_result["ok"]:
		return manifest_result
	var manifest: Dictionary = manifest_result["data"]
	if int(manifest.get("schema_version", 0)) != SUPPORTED_MANIFEST_SCHEMA:
		return _failure("Unsupported manifest schema_version.")

	var style_path := String(manifest.get("style_profile", ""))
	var style_result := _load_json_dictionary(style_path)
	if not style_result["ok"]:
		return style_result
	var style: Dictionary = style_result["data"]
	if int(style.get("schema_version", 0)) != SUPPORTED_STYLE_SCHEMA:
		return _failure("Unsupported Style Profile schema_version.")
	if String(style.get("construction_mode", "")) != "shape_guided":
		return _failure("Style Profile construction_mode must be shape_guided.")
	var palette_result := _parse_palette(style)
	if not palette_result["ok"]:
		return palette_result
	var palette: Dictionary = palette_result["palette"]

	var source_path := String(manifest.get("source_image", ""))
	var image_result := _load_image(source_path)
	if not image_result["ok"]:
		return image_result
	var source_image: Image = image_result["image"]
	var source_hash := _sha256_file(source_path)
	if source_hash.is_empty():
		return _failure("Failed to hash source image.")

	var analysis_size := _array_to_vector2i(style.get("analysis_size_px", []))
	if analysis_size.x <= 0 or analysis_size.y <= 0:
		return _failure("Style Profile analysis_size_px is invalid.")
	var image := source_image.duplicate()
	image.resize(analysis_size.x, analysis_size.y, Image.INTERPOLATE_LANCZOS)

	var key_color := Color(String(manifest.get(
		"background_key",
		style.get("background_key", "#ff00ff")
	)))
	var key_threshold := float(style.get("background_distance_threshold", 0.18))
	var mask := _build_foreground_mask(image, key_color, key_threshold)
	var outline_result := _extract_largest_outline(
		mask,
		float(style.get("rdp_epsilon_px", 3.0))
	)
	if not outline_result["ok"]:
		return outline_result
	var raw_outline: PackedVector2Array = outline_result["outline"]
	var minimum_outline_edge_length := float(
		style.get("minimum_outline_edge_length_px", 8.0)
	)
	var minimum_visible_area := float(
		style.get("minimum_visible_face_area_px2", 120.0)
	)
	var minimum_visible_altitude := float(
		style.get("minimum_visible_face_altitude_px", 8.0)
	)
	if minimum_outline_edge_length <= 0.0:
		return _failure("Style Profile minimum_outline_edge_length_px is invalid.")
	if minimum_visible_area <= 0.0:
		return _failure("Style Profile minimum_visible_face_area_px2 is invalid.")
	if minimum_visible_altitude <= 0.0:
		return _failure("Style Profile minimum_visible_face_altitude_px is invalid.")
	var outline_cleanup := _clean_outline_nodes(
		raw_outline,
		minimum_outline_edge_length,
		minimum_visible_area,
		minimum_visible_altitude
	)
	if not bool(outline_cleanup.get("ok", false)):
		return outline_cleanup
	var outline: PackedVector2Array = outline_cleanup["outline"]
	var source_bounds := _bounds_for_points(outline)
	var internal_shape_result := _extract_internal_shapes(
		image,
		mask,
		source_bounds,
		manifest.get("internal_shape_guides", []),
		style,
		palette
	)
	if not bool(internal_shape_result.get("ok", false)):
		return internal_shape_result
	var internal_shapes: Array = internal_shape_result["shapes"]
	var intersected_outline := _insert_internal_shape_intersections(
		outline,
		internal_shapes
	)
	var constructed_outline_result := _clean_shape_guided_outline(
		intersected_outline,
		internal_shapes,
		minimum_outline_edge_length,
		minimum_visible_area,
		minimum_visible_altitude
	)
	if not bool(constructed_outline_result.get("ok", false)):
		return constructed_outline_result
	var mesh_outline: PackedVector2Array = constructed_outline_result["outline"]
	var actual_minimum_outline_edge := _minimum_polygon_edge_length(mesh_outline)
	if actual_minimum_outline_edge < minimum_outline_edge_length:
		return _failure(
			"Internal shape intersections created an outline edge below the minimum length."
		)

	var triangulation_result := _triangulate_constructed_mesh(
		mesh_outline,
		internal_shapes,
		style,
		minimum_visible_area,
		minimum_visible_altitude
	)
	if not triangulation_result["ok"]:
		return triangulation_result

	var vertices: PackedVector2Array = triangulation_result["vertices"]
	var triangles: Array = triangulation_result["triangles"]
	var topology: Dictionary = triangulation_result["topology"]
	var actual_spacing := int(triangulation_result["sample_spacing_px"])
	var pivot := source_bounds.position + source_bounds.size * 0.5
	var local_vertices := PackedVector2Array()
	for point: Vector2 in vertices:
		local_vertices.append(point - pivot)
	var local_outline := PackedVector2Array()
	for point: Vector2 in mesh_outline:
		local_outline.append(point - pivot)
	var region_guides: Dictionary = manifest.get("region_guides", {})
	var face_records := _build_face_records(
		image,
		vertices,
		triangles,
		pivot,
		source_bounds,
		palette,
		region_guides,
		internal_shapes
	)
	if face_records.is_empty():
		return _failure("No valid polygon faces remained after palette assignment.")
	var emphasis_result := _apply_facet_emphasis(
		face_records,
		manifest.get("facet_emphasis", []),
		source_bounds,
		pivot,
		palette
	)
	if not bool(emphasis_result.get("ok", false)):
		return emphasis_result
	_assign_clear_order(face_records)

	var local_bounds := Rect2(source_bounds.position - pivot, source_bounds.size)
	var collision_points := Geometry2D.convex_hull(local_outline)
	if collision_points.size() > 1 and collision_points[0].is_equal_approx(
		collision_points[collision_points.size() - 1]
	):
		collision_points.remove_at(collision_points.size() - 1)
	var anchors := _build_anchors(manifest, local_bounds)
	var region_counts := _count_regions(face_records)
	var local_internal_shapes := _localize_internal_shapes(
		internal_shapes,
		pivot
	)

	var output := {
		"schema_version": 1,
		"asset_id": String(manifest.get("asset_id", "")),
		"source": {
			"sha256": source_hash,
			"analysis_size_px": _vector2i_to_array(analysis_size),
		"original_size_px": _vector2i_to_array(Vector2i(source_image.get_size())),
		"background_key": key_color.to_html(false),
		},
		"style_id": String(style.get("style_id", "")),
		"palette": style.get("palette", {}).duplicate(true),
		"bounds": _rect_to_dictionary(local_bounds),
		"source_bounds_px": _rect_to_dictionary(source_bounds),
		"pivot": _vector2_to_array(pivot),
		"vertices": _packed_vector2_to_arrays(local_vertices),
		"faces": face_records,
		"regions": {
			"left_page": {"face_count": int(region_counts.get("left_page", 0))},
			"right_page": {"face_count": int(region_counts.get("right_page", 0))},
			"spine": {"face_count": int(region_counts.get("spine", 0))},
		},
		"construction": {
			"mode": String(style["construction_mode"]),
			"source_usage": [
				"outer_shape",
				"internal_shape",
				"color_reference",
			],
			"generated_geometry": true,
			"runtime_source_texture": false,
		},
		"internal_shapes": local_internal_shapes,
		"clear_order": "outer_edge_to_spine",
		"outline": _packed_vector2_to_arrays(local_outline),
		"anchors": anchors,
		"collision": {
			"strategy": String((manifest.get("collision", {}) as Dictionary).get(
				"strategy",
				"convex_hull"
			)),
			"static_during_visual_animation": bool(
				(manifest.get("collision", {}) as Dictionary).get(
					"static_during_visual_animation",
					true
				)
			),
			"convex_hull": _packed_vector2_to_arrays(collision_points),
		},
		"stats": {
			"logical_vertex_count": local_vertices.size(),
			"face_count": face_records.size(),
			"outline_vertex_count": local_outline.size(),
			"connected_components": int(topology["edge_connected_components"]),
			"watertight": true,
			"boundary_edge_count": int(topology["boundary_edge_count"]),
			"interior_edge_count": int(topology["interior_edge_count"]),
			"draw_surfaces": 1,
			"construction_mode": "shape_guided",
			"internal_shape_count": internal_shapes.size(),
			"protected_internal_edge_count": int(
				triangulation_result["protected_internal_edge_count"]
			),
			"sample_spacing_px": actual_spacing,
			"minimum_triangle_area_px2": float(
				triangulation_result["minimum_triangle_area_px2"]
			),
			"minimum_face_altitude_px": float(
				triangulation_result["minimum_face_altitude_px"]
			),
			"minimum_outline_edge_length_px": float(
				actual_minimum_outline_edge
			),
			"removed_outline_vertex_count":
				raw_outline.size() - outline.size(),
			"constructed_outline_removed_vertex_count":
				intersected_outline.size() - mesh_outline.size(),
			"minimum_visible_face_area_px2": minimum_visible_area,
			"minimum_visible_face_altitude_px": minimum_visible_altitude,
			"emphasized_face_count": int(emphasis_result.get("count", 0)),
		},
	}
	return {
		"ok": true,
		"data": output,
		"output_path": String(manifest.get("output_asset", "")),
	}


func write_compiled_result(result: Dictionary) -> Error:
	if not bool(result.get("ok", false)):
		return ERR_INVALID_DATA
	var output_path := String(result.get("output_path", ""))
	if output_path.is_empty():
		return ERR_INVALID_PARAMETER
	var absolute_path := ProjectSettings.globalize_path(output_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(result["data"], "\t", true, true) + "\n")
	return OK


func _clean_outline_nodes(
	source_outline: PackedVector2Array,
	minimum_edge_length: float,
	minimum_face_area: float,
	minimum_face_altitude: float
) -> Dictionary:
	var outline := source_outline.duplicate()
	if outline.size() < 3:
		return _failure("Foreground outline has fewer than three vertices.")
	var maximum_pass_count := source_outline.size() * 3
	for _pass_index in range(maximum_pass_count):
		if outline.size() <= 3:
			break
		var remove_index := _short_outline_node_index(
			outline,
			minimum_edge_length
		)
		if remove_index < 0:
			remove_index = _invalid_outline_ear_index(
				outline,
				minimum_face_area,
				minimum_face_altitude
			)
		if remove_index < 0:
			break
		outline.remove_at(remove_index)

	var base_indices := Geometry2D.triangulate_polygon(outline)
	if base_indices.size() < 3:
		return _failure("Cleaned foreground outline could not be triangulated.")
	for base_index in range(0, base_indices.size(), 3):
		var a: Vector2 = outline[int(base_indices[base_index])]
		var b: Vector2 = outline[int(base_indices[base_index + 1])]
		var c: Vector2 = outline[int(base_indices[base_index + 2])]
		if not _triangle_meets_visual_threshold(
			a,
			b,
			c,
			minimum_face_area,
			minimum_face_altitude
		):
			return _failure(
				"Outline cleanup could not eliminate every undersized boundary face."
			)
	var minimum_found_edge := INF
	for point_index in range(outline.size()):
		minimum_found_edge = minf(
			minimum_found_edge,
			outline[point_index].distance_to(
				outline[(point_index + 1) % outline.size()]
			)
		)
	if minimum_found_edge < minimum_edge_length:
		return _failure("Outline cleanup left an edge below the minimum length.")
	return {
		"ok": true,
		"outline": outline,
		"minimum_outline_edge_length_px": minimum_found_edge,
	}


func _short_outline_node_index(
	outline: PackedVector2Array,
	minimum_edge_length: float
) -> int:
	var best_index := -1
	var best_deviation := INF
	var best_adjacent_length := INF
	for point_index in range(outline.size()):
		var previous := outline[
			(point_index - 1 + outline.size()) % outline.size()
		]
		var current := outline[point_index]
		var next := outline[(point_index + 1) % outline.size()]
		var adjacent_length := minf(
			previous.distance_to(current),
			current.distance_to(next)
		)
		if adjacent_length >= minimum_edge_length:
			continue
		var deviation := _point_segment_distance(current, previous, next)
		if (
			deviation < best_deviation
			or (
				is_equal_approx(deviation, best_deviation)
				and adjacent_length < best_adjacent_length
			)
		):
			best_index = point_index
			best_deviation = deviation
			best_adjacent_length = adjacent_length
	return best_index


func _invalid_outline_ear_index(
	outline: PackedVector2Array,
	minimum_face_area: float,
	minimum_face_altitude: float
) -> int:
	var base_indices := Geometry2D.triangulate_polygon(outline)
	if base_indices.size() < 3:
		return -1
	var best_index := -1
	var worst_quality := INF
	for base_index in range(0, base_indices.size(), 3):
		var triangle_indices: Array[int] = [
			int(base_indices[base_index]),
			int(base_indices[base_index + 1]),
			int(base_indices[base_index + 2]),
		]
		var a := outline[triangle_indices[0]]
		var b := outline[triangle_indices[1]]
		var c := outline[triangle_indices[2]]
		if _triangle_meets_visual_threshold(
			a,
			b,
			c,
			minimum_face_area,
			minimum_face_altitude
		):
			continue
		for candidate_index: int in triangle_indices:
			var previous_index := (
				candidate_index - 1 + outline.size()
			) % outline.size()
			var next_index := (candidate_index + 1) % outline.size()
			if (
				not triangle_indices.has(previous_index)
				or not triangle_indices.has(next_index)
			):
				continue
			var area := absf(_signed_triangle_area(a, b, c))
			var altitude := _triangle_minimum_altitude(a, b, c)
			var quality := minf(
				area / minimum_face_area,
				altitude / minimum_face_altitude
			)
			if quality < worst_quality:
				worst_quality = quality
				best_index = candidate_index
	return best_index


func _point_segment_distance(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2
) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(segment_start)
	var progress := clampf(
		(point - segment_start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(segment_start + segment * progress)


func _extract_internal_shapes(
	image: Image,
	mask: BitMap,
	source_bounds: Rect2,
	guides_value: Variant,
	style: Dictionary,
	palette: Dictionary
) -> Dictionary:
	if not guides_value is Array:
		return _failure("Manifest internal_shape_guides must be an array.")
	var extraction_config: Dictionary = style.get(
		"internal_shape_extraction",
		{}
	)
	var shapes: Array = []
	for guide_value: Variant in guides_value:
		if not guide_value is Dictionary:
			return _failure(
				"Manifest internal_shape_guides entries must be dictionaries."
			)
		var guide: Dictionary = guide_value
		var shape_id := String(guide.get("id", ""))
		var kind := String(guide.get("kind", ""))
		if shape_id.is_empty():
			return _failure("Internal shape guide id is empty.")
		if kind != "vertical_band":
			return _failure(
				"Unsupported internal shape guide kind: %s." % kind
			)
		var center_ratio := float(guide.get("center_ratio", 0.5))
		var search_half_width_ratio := float(
			guide.get("search_half_width_ratio", 0.1)
		)
		if (
			center_ratio <= 0.0
			or center_ratio >= 1.0
			or search_half_width_ratio <= 0.0
			or search_half_width_ratio >= 0.5
		):
			return _failure(
				"Internal vertical band search ratios are invalid."
			)
		var sample_rows_value: Variant = guide.get(
			"sample_y_ratios",
			[0.25, 0.5, 0.75]
		)
		if (
			not sample_rows_value is Array
			or (sample_rows_value as Array).is_empty()
		):
			return _failure(
				"Internal vertical band sample_y_ratios are invalid."
			)
		var expected_x := (
			source_bounds.position.x
			+ source_bounds.size.x * center_ratio
		)
		var search_half_width := maxf(
			source_bounds.size.x * search_half_width_ratio,
			2.0
		)
		var detected_centers: Array[float] = []
		var detected_widths: Array[float] = []
		var detected_colors: Array[Color] = []
		for row_value: Variant in sample_rows_value:
			var row_ratio := float(row_value)
			if row_ratio <= 0.0 or row_ratio >= 1.0:
				return _failure(
					"Internal vertical band sample row is outside 0..1."
				)
			var y := source_bounds.position.y + source_bounds.size.y * row_ratio
			var row_result := _detect_vertical_band_row(
				image,
				mask,
				y,
				expected_x,
				search_half_width,
				extraction_config
			)
			if not bool(row_result.get("ok", false)):
				continue
			detected_centers.append(float(row_result["center_x"]))
			detected_widths.append(float(row_result["source_width_px"]))
			detected_colors.append(row_result["source_color"])
		var minimum_sample_count := int(
			extraction_config.get("minimum_sample_count", 3)
		)
		if detected_centers.size() < minimum_sample_count:
			return _failure(
				"Internal vertical band %s did not produce enough source samples."
				% shape_id
			)
		detected_centers.sort()
		detected_widths.sort()
		var center_x := detected_centers[detected_centers.size() / 2]
		var source_width := detected_widths[detected_widths.size() / 2]
		var minimum_width := float(
			guide.get(
				"minimum_constructed_width_px",
				extraction_config.get("minimum_constructed_band_width_px", 20.0)
			)
		)
		var maximum_width := float(
			guide.get(
				"maximum_constructed_width_px",
				extraction_config.get("maximum_constructed_band_width_px", 28.0)
			)
		)
		if minimum_width <= 0.0 or maximum_width < minimum_width:
			return _failure(
				"Internal vertical band constructed width is invalid."
			)
		var constructed_width := clampf(
			maxf(source_width, minimum_width),
			minimum_width,
			maximum_width
		)
		var left_x := center_x - constructed_width * 0.5
		var right_x := center_x + constructed_width * 0.5
		if (
			left_x <= source_bounds.position.x
			or right_x >= source_bounds.end.x
		):
			return _failure(
				"Internal vertical band extends outside the foreground bounds."
			)
		var source_color := _average_colors(detected_colors)
		var palette_role := _nearest_palette_role(source_color, palette)
		shapes.append({
			"id": shape_id,
			"kind": kind,
			"region": String(guide.get("region", shape_id)),
			"center_x": center_x,
			"left_x": left_x,
			"right_x": right_x,
			"source_width_px": source_width,
			"constructed_width_px": constructed_width,
			"source_color": source_color,
			"palette_role": palette_role,
			"sample_count": detected_centers.size(),
		})
	if shapes.size() > 1:
		return _failure(
			"Shape-guided mesh v1 supports one internal vertical band."
		)
	return {"ok": true, "shapes": shapes}


func _detect_vertical_band_row(
	image: Image,
	mask: BitMap,
	y_value: float,
	expected_x: float,
	search_half_width: float,
	config: Dictionary
) -> Dictionary:
	var y := clampi(roundi(y_value), 0, image.get_height() - 1)
	var search_start := clampi(
		floori(expected_x - search_half_width),
		0,
		image.get_width() - 1
	)
	var search_end := clampi(
		ceili(expected_x + search_half_width),
		0,
		image.get_width() - 1
	)
	var probe_distance := maxi(
		int(config.get("contrast_probe_distance_px", 10)),
		1
	)
	var darkness_weight := float(config.get("darkness_weight", 0.75))
	var center_bias := float(config.get("center_bias", 0.04))
	var minimum_contrast := float(config.get("minimum_contrast", 0.08))
	var best_x := -1
	var best_score := -INF
	for x in range(search_start, search_end + 1):
		var left_x := clampi(x - probe_distance, 0, image.get_width() - 1)
		var right_x := clampi(x + probe_distance, 0, image.get_width() - 1)
		if (
			not mask.get_bit(x, y)
			or not mask.get_bit(left_x, y)
			or not mask.get_bit(right_x, y)
		):
			continue
		var candidate := image.get_pixel(x, y)
		var neighbor := _average_colors([
			image.get_pixel(left_x, y),
			image.get_pixel(right_x, y),
		])
		var contrast := _color_distance(candidate, neighbor)
		var darkness := maxf(
			_color_luminance(neighbor) - _color_luminance(candidate),
			0.0
		)
		var distance_ratio := (
			absf(float(x) - expected_x) / search_half_width
		)
		var score := (
			contrast
			+ darkness * darkness_weight
			- distance_ratio * center_bias
		)
		if score > best_score:
			best_score = score
			best_x = x
	if best_x < 0 or best_score < minimum_contrast:
		return {"ok": false}

	var source_color := image.get_pixel(best_x, y)
	var similarity_threshold := float(
		config.get("band_color_similarity_threshold", 0.16)
	)
	var left_edge := best_x
	var right_edge := best_x
	while left_edge > search_start:
		var next_x := left_edge - 1
		if (
			not mask.get_bit(next_x, y)
			or _color_distance(
				image.get_pixel(next_x, y),
				source_color
			) > similarity_threshold
		):
			break
		left_edge = next_x
	while right_edge < search_end:
		var next_x := right_edge + 1
		if (
			not mask.get_bit(next_x, y)
			or _color_distance(
				image.get_pixel(next_x, y),
				source_color
			) > similarity_threshold
		):
			break
		right_edge = next_x
	return {
		"ok": true,
		"center_x": float(best_x),
		"source_width_px": float(right_edge - left_edge + 1),
		"source_color": source_color,
	}


func _average_colors(colors: Array) -> Color:
	if colors.is_empty():
		return Color.BLACK
	var sum := Vector3.ZERO
	for color_value: Variant in colors:
		var color: Color = color_value
		sum += Vector3(color.r, color.g, color.b)
	sum /= float(colors.size())
	return Color(sum.x, sum.y, sum.z)


func _color_distance(first: Color, second: Color) -> float:
	return Vector3(
		first.r - second.r,
		first.g - second.g,
		first.b - second.b
	).length()


func _color_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _insert_internal_shape_intersections(
	outline: PackedVector2Array,
	internal_shapes: Array
) -> PackedVector2Array:
	if internal_shapes.is_empty():
		return outline.duplicate()
	var cut_positions: Array[float] = []
	for shape_value: Variant in internal_shapes:
		var shape: Dictionary = shape_value
		cut_positions.append(float(shape["left_x"]))
		cut_positions.append(float(shape["right_x"]))
	cut_positions.sort()
	var result := PackedVector2Array()
	for point_index in range(outline.size()):
		var current := outline[point_index]
		var next := outline[(point_index + 1) % outline.size()]
		var edge := next - current
		var edge_points: Array = [{"progress": 0.0, "point": current}]
		if not is_zero_approx(edge.x):
			for cut_x: float in cut_positions:
				var progress := (cut_x - current.x) / edge.x
				if progress > 0.0001 and progress < 0.9999:
					edge_points.append({
						"progress": progress,
						"point": current.lerp(next, progress),
					})
		edge_points.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return float(first["progress"]) < float(second["progress"])
		)
		for edge_point_value: Variant in edge_points:
			var edge_point: Vector2 = (edge_point_value as Dictionary)["point"]
			if (
				result.is_empty()
				or not result[result.size() - 1].is_equal_approx(edge_point)
			):
				result.append(edge_point)
	return result


func _minimum_polygon_edge_length(polygon: PackedVector2Array) -> float:
	if polygon.size() < 2:
		return 0.0
	var minimum_length := INF
	for point_index in range(polygon.size()):
		minimum_length = minf(
			minimum_length,
			polygon[point_index].distance_to(
				polygon[(point_index + 1) % polygon.size()]
			)
		)
	return minimum_length


func _clean_shape_guided_outline(
	source_outline: PackedVector2Array,
	internal_shapes: Array,
	minimum_edge_length: float,
	minimum_face_area: float,
	minimum_face_altitude: float
) -> Dictionary:
	var outline := source_outline.duplicate()
	var protected_x_values: Array[float] = []
	for shape_value: Variant in internal_shapes:
		var shape: Dictionary = shape_value
		if String(shape.get("kind", "")) != "vertical_band":
			continue
		protected_x_values.append(float(shape["left_x"]))
		protected_x_values.append(float(shape["right_x"]))
	var maximum_pass_count := source_outline.size() * 2
	for _pass_index in range(maximum_pass_count):
		if outline.size() <= 3:
			break
		var remove_index := _short_unprotected_outline_node_index(
			outline,
			protected_x_values,
			minimum_edge_length
		)
		if remove_index < 0:
			remove_index = _invalid_unprotected_outline_ear_index(
				outline,
				protected_x_values,
				minimum_face_area,
				minimum_face_altitude
			)
		if remove_index < 0:
			break
		outline.remove_at(remove_index)
	var base_indices := Geometry2D.triangulate_polygon(outline)
	if base_indices.size() < 3:
		return _failure(
			"Shape-guided outline could not be triangulated after cleanup."
		)
	return {"ok": true, "outline": outline}


func _short_unprotected_outline_node_index(
	outline: PackedVector2Array,
	protected_x_values: Array[float],
	minimum_edge_length: float
) -> int:
	var best_index := -1
	var best_deviation := INF
	for point_index in range(outline.size()):
		var current := outline[point_index]
		if _point_uses_protected_x(current, protected_x_values):
			continue
		var previous := outline[
			(point_index - 1 + outline.size()) % outline.size()
		]
		var next := outline[(point_index + 1) % outline.size()]
		var adjacent_length := minf(
			previous.distance_to(current),
			current.distance_to(next)
		)
		if adjacent_length >= minimum_edge_length:
			continue
		var deviation := _point_segment_distance(current, previous, next)
		if deviation < best_deviation:
			best_index = point_index
			best_deviation = deviation
	return best_index


func _invalid_unprotected_outline_ear_index(
	outline: PackedVector2Array,
	protected_x_values: Array[float],
	minimum_face_area: float,
	minimum_face_altitude: float
) -> int:
	var base_indices := Geometry2D.triangulate_polygon(outline)
	if base_indices.size() < 3:
		return -1
	var best_index := -1
	var worst_quality := INF
	for base_index in range(0, base_indices.size(), 3):
		var triangle_indices: Array[int] = [
			int(base_indices[base_index]),
			int(base_indices[base_index + 1]),
			int(base_indices[base_index + 2]),
		]
		var a := outline[triangle_indices[0]]
		var b := outline[triangle_indices[1]]
		var c := outline[triangle_indices[2]]
		if _triangle_meets_visual_threshold(
			a,
			b,
			c,
			minimum_face_area,
			minimum_face_altitude
		):
			continue
		for candidate_index: int in triangle_indices:
			var candidate := outline[candidate_index]
			if _point_uses_protected_x(candidate, protected_x_values):
				continue
			var previous_index := (
				candidate_index - 1 + outline.size()
			) % outline.size()
			var next_index := (candidate_index + 1) % outline.size()
			if (
				not triangle_indices.has(previous_index)
				or not triangle_indices.has(next_index)
			):
				continue
			var area := absf(_signed_triangle_area(a, b, c))
			var altitude := _triangle_minimum_altitude(a, b, c)
			var quality := minf(
				area / minimum_face_area,
				altitude / minimum_face_altitude
			)
			if quality < worst_quality:
				worst_quality = quality
				best_index = candidate_index
	return best_index


func _point_uses_protected_x(
	point: Vector2,
	protected_x_values: Array[float]
) -> bool:
	for protected_x: float in protected_x_values:
		if is_equal_approx(point.x, protected_x):
			return true
	return false


func _triangulate_constructed_mesh(
	outline: PackedVector2Array,
	internal_shapes: Array,
	style: Dictionary,
	minimum_visible_area: float,
	minimum_visible_altitude: float
) -> Dictionary:
	var target_config: Dictionary = style.get("target_face_count", {})
	var target_min := int(target_config.get("min", 48))
	var target_max := int(target_config.get("max", 80))
	var hard_max := int(target_config.get("hard_max", 160))
	var minimum_area := float(style.get("minimum_triangle_area_px2", 3.0))
	var partitions_result := _build_constructed_partitions(
		outline,
		internal_shapes
	)
	if not bool(partitions_result.get("ok", false)):
		return partitions_result
	var partitions: Array = partitions_result["partitions"]
	var output_points := outline.duplicate()
	var point_indices: Dictionary = {}
	for point_index in range(output_points.size()):
		point_indices[_point_key(output_points[point_index])] = point_index
	var triangles: Array = []
	for partition_index in range(partitions.size()):
		var partition: PackedVector2Array = partitions[partition_index]
		var base_indices := Geometry2D.triangulate_polygon(partition)
		if base_indices.size() < 3:
			return _failure(
				"Constructed shape partition could not be triangulated."
			)
		var local_to_global: Array[int] = []
		for point: Vector2 in partition:
			local_to_global.append(
				_find_or_append_point(output_points, point_indices, point)
			)
		for base_index in range(0, base_indices.size(), 3):
			var triangle := _oriented_triangle(
				local_to_global[int(base_indices[base_index])],
				local_to_global[int(base_indices[base_index + 1])],
				local_to_global[int(base_indices[base_index + 2])],
				output_points
			)
			var a := output_points[int(triangle[0])]
			var b := output_points[int(triangle[1])]
			var c := output_points[int(triangle[2])]
			if (
				absf(_signed_triangle_area(a, b, c)) <= minimum_area
				or not _triangle_meets_visual_threshold(
					a,
					b,
					c,
					minimum_visible_area,
					minimum_visible_altitude
				)
			):
				return _failure(
					(
						"Constructed partition %d produced an undersized face "
						+ "(area %.2f, altitude %.2f, points %s / %s / %s)."
					)
					% [
						partition_index,
						absf(_signed_triangle_area(a, b, c)),
						_triangle_minimum_altitude(a, b, c),
						str(a),
						str(b),
						str(c),
					]
				)
			triangles.append(triangle)

	while triangles.size() < target_min:
		var largest_face_index := -1
		var largest_face_area := 0.0
		var largest_split_point := Vector2.ZERO
		for face_index in range(triangles.size()):
			var face: Array = triangles[face_index]
			var face_a := output_points[int(face[0])]
			var face_b := output_points[int(face[1])]
			var face_c := output_points[int(face[2])]
			var face_area := absf(_signed_triangle_area(
				face_a,
				face_b,
				face_c
			))
			var candidate_split := (face_a + face_b + face_c) / 3.0
			if not _triangle_split_meets_visual_threshold(
				face_a,
				face_b,
				face_c,
				candidate_split,
				minimum_visible_area,
				minimum_visible_altitude
			):
				continue
			if face_area > largest_face_area:
				largest_face_area = face_area
				largest_face_index = face_index
				largest_split_point = candidate_split
		if largest_face_index < 0:
			return _failure(
				"Unable to reach the shape-guided face target without undersized faces."
			)
		var largest_face: Array = triangles[largest_face_index]
		var split_index := output_points.size()
		output_points.append(largest_split_point)
		triangles.remove_at(largest_face_index)
		triangles.append(_oriented_triangle(
			int(largest_face[0]),
			int(largest_face[1]),
			split_index,
			output_points
		))
		triangles.append(_oriented_triangle(
			int(largest_face[1]),
			int(largest_face[2]),
			split_index,
			output_points
		))
		triangles.append(_oriented_triangle(
			int(largest_face[2]),
			int(largest_face[0]),
			split_index,
			output_points
		))
	if triangles.size() > target_max or triangles.size() > hard_max:
		return _failure(
			"Shape-guided face target exceeded: %d." % triangles.size()
		)
	var topology := _analyze_watertight_topology(
		triangles,
		outline.size()
	)
	if not bool(topology.get("ok", false)):
		return _failure(String(topology.get(
			"error",
			"Shape-guided triangulation is not watertight."
		)))
	var minimum_found := INF
	var minimum_found_altitude := INF
	for face_value: Variant in triangles:
		var face: Array = face_value
		var face_a := output_points[int(face[0])]
		var face_b := output_points[int(face[1])]
		var face_c := output_points[int(face[2])]
		minimum_found = minf(
			minimum_found,
			absf(_signed_triangle_area(face_a, face_b, face_c))
		)
		minimum_found_altitude = minf(
			minimum_found_altitude,
			_triangle_minimum_altitude(face_a, face_b, face_c)
		)
	return {
		"ok": true,
		"vertices": output_points,
		"triangles": triangles,
		"minimum_triangle_area_px2": minimum_found,
		"minimum_face_altitude_px": minimum_found_altitude,
		"protected_internal_edge_count":
			_count_protected_internal_edges(
				triangles,
				output_points,
				internal_shapes
			),
		"sample_spacing_px": 0,
		"topology": topology,
	}


func _build_constructed_partitions(
	outline: PackedVector2Array,
	internal_shapes: Array
) -> Dictionary:
	if internal_shapes.is_empty():
		return {"ok": true, "partitions": [outline.duplicate()]}
	var shape: Dictionary = internal_shapes[0]
	if String(shape.get("kind", "")) != "vertical_band":
		return _failure("Constructed partition kind is unsupported.")
	var left_x := float(shape["left_x"])
	var right_x := float(shape["right_x"])
	var left_partition := _clip_polygon_vertical(
		outline,
		left_x,
		true
	)
	var band_partition := _clip_polygon_vertical(
		_clip_polygon_vertical(outline, left_x, false),
		right_x,
		true
	)
	var right_partition := _clip_polygon_vertical(
		outline,
		right_x,
		false
	)
	var partitions: Array = [
		_sanitize_polygon(left_partition),
		_sanitize_polygon(band_partition),
		_sanitize_polygon(right_partition),
	]
	for partition_value: Variant in partitions:
		var partition: PackedVector2Array = partition_value
		if partition.size() < 3:
			return _failure(
				"Internal shape produced an empty mesh partition."
			)
	return {"ok": true, "partitions": partitions}


func _clip_polygon_vertical(
	polygon: PackedVector2Array,
	boundary_x: float,
	keep_left: bool
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point_index in range(polygon.size()):
		var current := polygon[point_index]
		var next := polygon[(point_index + 1) % polygon.size()]
		var current_inside := (
			current.x <= boundary_x + 0.0001
			if keep_left
			else current.x >= boundary_x - 0.0001
		)
		var next_inside := (
			next.x <= boundary_x + 0.0001
			if keep_left
			else next.x >= boundary_x - 0.0001
		)
		if current_inside:
			result.append(current)
		if current_inside == next_inside or is_equal_approx(current.x, next.x):
			continue
		var progress := (boundary_x - current.x) / (next.x - current.x)
		result.append(current.lerp(next, progress))
	return result


func _sanitize_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		if (
			result.is_empty()
			or not result[result.size() - 1].is_equal_approx(point)
		):
			result.append(point)
	if (
		result.size() > 1
		and result[0].is_equal_approx(result[result.size() - 1])
	):
		result.remove_at(result.size() - 1)
	return result


func _find_or_append_point(
	points: PackedVector2Array,
	point_indices: Dictionary,
	point: Vector2
) -> int:
	var key := _point_key(point)
	if point_indices.has(key):
		return int(point_indices[key])
	var point_index := points.size()
	points.append(point)
	point_indices[key] = point_index
	return point_index


func _point_key(point: Vector2) -> String:
	return "%d:%d" % [roundi(point.x * 1000.0), roundi(point.y * 1000.0)]


func _count_protected_internal_edges(
	triangles: Array,
	vertices: PackedVector2Array,
	internal_shapes: Array
) -> int:
	if internal_shapes.is_empty():
		return 0
	var cut_positions: Array[float] = []
	for shape_value: Variant in internal_shapes:
		var shape: Dictionary = shape_value
		cut_positions.append(float(shape["left_x"]))
		cut_positions.append(float(shape["right_x"]))
	var edge_owners: Dictionary = {}
	for face_value: Variant in triangles:
		var face: Array = face_value
		for edge_index in range(3):
			var first := int(face[edge_index])
			var second := int(face[(edge_index + 1) % 3])
			var key := _edge_key(first, second)
			edge_owners[key] = int(edge_owners.get(key, 0)) + 1
	var protected_count := 0
	for edge_value: Variant in edge_owners:
		if int(edge_owners[edge_value]) != 2:
			continue
		var edge_parts := String(edge_value).split(":")
		var first_index := int(edge_parts[0])
		var second_index := int(edge_parts[1])
		for cut_x: float in cut_positions:
			if (
				is_equal_approx(vertices[first_index].x, cut_x)
				and is_equal_approx(vertices[second_index].x, cut_x)
			):
				protected_count += 1
				break
	return protected_count


func _localize_internal_shapes(
	internal_shapes: Array,
	pivot: Vector2
) -> Array:
	var result: Array = []
	for shape_value: Variant in internal_shapes:
		var shape: Dictionary = shape_value
		var source_color: Color = shape["source_color"]
		result.append({
			"id": String(shape["id"]),
			"kind": String(shape["kind"]),
			"region": String(shape["region"]),
			"center_x": _round_number(float(shape["center_x"]) - pivot.x),
			"left_x": _round_number(float(shape["left_x"]) - pivot.x),
			"right_x": _round_number(float(shape["right_x"]) - pivot.x),
			"source_width_px": _round_number(float(shape["source_width_px"])),
			"constructed_width_px": _round_number(
				float(shape["constructed_width_px"])
			),
			"source_color": source_color.to_html(false),
			"palette_role": String(shape["palette_role"]),
			"sample_count": int(shape["sample_count"]),
		})
	return result


func _triangulate_with_target(
	image: Image,
	mask: BitMap,
	outline: PackedVector2Array,
	style: Dictionary,
	minimum_visible_area: float,
	minimum_visible_altitude: float
) -> Dictionary:
	var target_config: Dictionary = style.get("target_face_count", {})
	var target_min := int(target_config.get("min", 70))
	var target_max := int(target_config.get("max", 140))
	var hard_max := int(target_config.get("hard_max", 160))
	var base_spacing := int(style.get("interior_sample_spacing_px", 24))
	var minimum_area := float(style.get("minimum_triangle_area_px2", 3.0))
	var candidates: Array[int] = [base_spacing]
	for offset in range(2, 15, 2):
		candidates.append(base_spacing + offset)
		if base_spacing - offset >= 12:
			candidates.append(base_spacing - offset)

	var best_result: Dictionary = {}
	var best_score := INF
	var last_error := ""
	for spacing: int in candidates:
		var points := _build_sample_points(
			outline,
			mask,
			spacing,
			float(style.get("sample_jitter_ratio", 0.16)),
			int(style.get("deterministic_seed", 20260730))
		)
		var triangulated := _triangulate_points(
			points,
			mask,
			outline,
			minimum_area,
			target_min,
			minimum_visible_area,
			minimum_visible_altitude
		)
		if not triangulated["ok"]:
			last_error = String(triangulated.get("error", ""))
			continue
		var triangles: Array = triangulated["triangles"]
		var face_count := triangles.size()
		if face_count <= hard_max and face_count >= target_min and face_count <= target_max:
			triangulated["sample_spacing_px"] = spacing
			return triangulated
		var distance_from_target := 0.0
		if face_count < target_min:
			distance_from_target = float(target_min - face_count)
		elif face_count > target_max:
			distance_from_target = float(face_count - target_max)
		if face_count > hard_max:
			distance_from_target += float(face_count - hard_max) * 4.0
		if distance_from_target < best_score:
			best_score = distance_from_target
			best_result = triangulated
			best_result["sample_spacing_px"] = spacing

	if best_result.is_empty():
		if not last_error.is_empty():
			return _failure(last_error)
		return _failure("Delaunay triangulation produced no connected face set.")
	var best_faces: Array = best_result["triangles"]
	if best_faces.size() > hard_max:
		return _failure(
			"Face hard limit exceeded: %d > %d." % [best_faces.size(), hard_max]
		)
	return best_result


func _triangulate_points(
	points: PackedVector2Array,
	_mask: BitMap,
	outline: PackedVector2Array,
	minimum_area: float,
	minimum_face_count: int,
	minimum_visible_area: float,
	minimum_visible_altitude: float
) -> Dictionary:
	var base_indices := Geometry2D.triangulate_polygon(outline)
	if base_indices.size() < 3:
		return _failure("Foreground outline could not be triangulated.")
	var output_points := outline.duplicate()
	var triangles: Array = []
	var minimum_found := INF
	for base_index in range(0, base_indices.size(), 3):
		var base_triangle := [
			int(base_indices[base_index]),
			int(base_indices[base_index + 1]),
			int(base_indices[base_index + 2]),
		]
		var base_a: Vector2 = outline[base_triangle[0]]
		var base_b: Vector2 = outline[base_triangle[1]]
		var base_c: Vector2 = outline[base_triangle[2]]
		var local_to_global: Array[int] = [
			base_triangle[0],
			base_triangle[1],
			base_triangle[2],
		]
		var base_area := absf(_signed_triangle_area(base_a, base_b, base_c))
		if not _triangle_meets_visual_threshold(
			base_a,
			base_b,
			base_c,
			minimum_visible_area,
			minimum_visible_altitude
		):
			return _failure(
				"Cleaned outline produced an undersized base triangle."
			)
		var has_interior_sample := false
		var interior_sample := (base_a + base_b + base_c) / 3.0
		for point_index in range(outline.size(), points.size()):
			var candidate := points[point_index]
			if _point_is_safely_inside_triangle(
				candidate,
				base_a,
				base_b,
				base_c,
				minimum_area
			):
				has_interior_sample = true
				interior_sample = candidate
				break
		if base_area > minimum_area * 3.2:
			var centroid := (base_a + base_b + base_c) / 3.0
			if has_interior_sample:
				centroid = centroid.lerp(interior_sample, 0.05)
			if _triangle_split_meets_visual_threshold(
				base_a,
				base_b,
				base_c,
				centroid,
				minimum_visible_area,
				minimum_visible_altitude
			):
				var centroid_index := output_points.size()
				output_points.append(centroid)
				local_to_global.append(centroid_index)

		var local_triangles: Array = [base_triangle]
		if local_to_global.size() == 4:
			var center_index := local_to_global[3]
			local_triangles = [
				[base_triangle[0], base_triangle[1], center_index],
				[base_triangle[1], base_triangle[2], center_index],
				[base_triangle[2], base_triangle[0], center_index],
			]
		for triangle_value: Variant in local_triangles:
			var triangle: Array = triangle_value
			var a: Vector2 = output_points[triangle[0]]
			var b: Vector2 = output_points[triangle[1]]
			var c: Vector2 = output_points[triangle[2]]
			var signed_area := _signed_triangle_area(a, b, c)
			var area := absf(signed_area)
			if (
				area <= minimum_area
				or not _triangle_meets_visual_threshold(
					a,
					b,
					c,
					minimum_visible_area,
					minimum_visible_altitude
				)
			):
				return _failure(
					"Constrained triangulation produced an undersized visible face."
				)
			if signed_area < 0.0:
				var swap: int = triangle[1]
				triangle[1] = triangle[2]
				triangle[2] = swap
			triangles.append(triangle)
			minimum_found = minf(minimum_found, area)

	var connected := _largest_connected_face_set(triangles)
	if connected.is_empty():
		return _failure("Filtered triangles do not form a connected component.")
	while connected.size() < minimum_face_count:
		var largest_face_index := -1
		var largest_face_area := 0.0
		var largest_split_point := Vector2.ZERO
		for face_index in range(connected.size()):
			var face: Array = connected[face_index]
			var face_a := output_points[int(face[0])]
			var face_b := output_points[int(face[1])]
			var face_c := output_points[int(face[2])]
			var face_area := absf(_signed_triangle_area(face_a, face_b, face_c))
			var candidate_split := (face_a + face_b + face_c) / 3.0
			if not _triangle_split_meets_visual_threshold(
				face_a,
				face_b,
				face_c,
				candidate_split,
				minimum_visible_area,
				minimum_visible_altitude
			):
				continue
			if face_area > largest_face_area:
				largest_face_area = face_area
				largest_face_index = face_index
				largest_split_point = candidate_split
		if largest_face_index < 0:
			return _failure(
				"Unable to reach the minimum face target without undersized faces."
			)
		var largest_face: Array = connected[largest_face_index]
		var split_index := output_points.size()
		output_points.append(largest_split_point)
		connected.remove_at(largest_face_index)
		connected.append(_oriented_triangle(
			int(largest_face[0]),
			int(largest_face[1]),
			split_index,
			output_points
		))
		connected.append(_oriented_triangle(
			int(largest_face[1]),
			int(largest_face[2]),
			split_index,
			output_points
		))
		connected.append(_oriented_triangle(
			int(largest_face[2]),
			int(largest_face[0]),
			split_index,
			output_points
		))
	var topology := _analyze_watertight_topology(connected, outline.size())
	if not bool(topology.get("ok", false)):
		return _failure(String(topology.get(
			"error",
			"Polygon triangulation is not watertight."
		)))
	minimum_found = INF
	var minimum_found_altitude := INF
	for face_value: Variant in connected:
		var face: Array = face_value
		var face_a := output_points[int(face[0])]
		var face_b := output_points[int(face[1])]
		var face_c := output_points[int(face[2])]
		minimum_found = minf(
			minimum_found,
			absf(_signed_triangle_area(face_a, face_b, face_c))
		)
		minimum_found_altitude = minf(
			minimum_found_altitude,
			_triangle_minimum_altitude(face_a, face_b, face_c)
		)
	return {
		"ok": true,
		"vertices": output_points,
		"triangles": connected,
		"minimum_triangle_area_px2": minimum_found,
		"minimum_face_altitude_px": minimum_found_altitude,
		"topology": topology,
	}


func _triangle_split_meets_visual_threshold(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	split_point: Vector2,
	minimum_area: float,
	minimum_altitude: float
) -> bool:
	return (
		_triangle_meets_visual_threshold(
			a,
			b,
			split_point,
			minimum_area,
			minimum_altitude
		)
		and _triangle_meets_visual_threshold(
			b,
			c,
			split_point,
			minimum_area,
			minimum_altitude
		)
		and _triangle_meets_visual_threshold(
			c,
			a,
			split_point,
			minimum_area,
			minimum_altitude
		)
	)


func _triangle_meets_visual_threshold(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	minimum_area: float,
	minimum_altitude: float
) -> bool:
	return (
		absf(_signed_triangle_area(a, b, c)) >= minimum_area
		and _triangle_minimum_altitude(a, b, c) >= minimum_altitude
	)


func _triangle_minimum_altitude(
	a: Vector2,
	b: Vector2,
	c: Vector2
) -> float:
	var maximum_edge := maxf(
		a.distance_to(b),
		maxf(b.distance_to(c), c.distance_to(a))
	)
	if maximum_edge <= 0.0:
		return 0.0
	return absf(_signed_triangle_area(a, b, c)) * 2.0 / maximum_edge


func _oriented_triangle(
	first: int,
	second: int,
	third: int,
	vertices: PackedVector2Array
) -> Array:
	if _signed_triangle_area(vertices[first], vertices[second], vertices[third]) >= 0.0:
		return [first, second, third]
	return [first, third, second]


func _build_sample_points(
	outline: PackedVector2Array,
	mask: BitMap,
	spacing: int,
	jitter_ratio: float,
	seed_value: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var point_keys: Dictionary = {}
	for point: Vector2 in outline:
		_append_unique_point(points, point_keys, point)

	var bounds := _bounds_for_points(outline)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var jitter := float(spacing) * jitter_ratio
	var start_x := ceili(bounds.position.x / float(spacing)) * spacing
	var start_y := ceili(bounds.position.y / float(spacing)) * spacing
	var end_x := floori(bounds.end.x)
	var end_y := floori(bounds.end.y)
	for y in range(start_y, end_y + 1, spacing):
		for x in range(start_x, end_x + 1, spacing):
			var candidate := Vector2(
				float(x) + random.randf_range(-jitter, jitter),
				float(y) + random.randf_range(-jitter, jitter)
			)
			if _point_is_foreground(candidate, mask, outline):
				_append_unique_point(points, point_keys, candidate)

	var center_x := bounds.position.x + bounds.size.x * 0.5
	for y in range(start_y, end_y + 1, maxi(12, spacing)):
		var spine_point := Vector2(center_x, float(y))
		if _point_is_foreground(spine_point, mask, outline):
			_append_unique_point(points, point_keys, spine_point)
	return points


func _point_is_safely_inside_triangle(
	point: Vector2,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	minimum_area: float
) -> bool:
	var total_area := absf(_signed_triangle_area(a, b, c))
	if total_area <= minimum_area:
		return false
	var first_area := absf(_signed_triangle_area(point, b, c))
	var second_area := absf(_signed_triangle_area(a, point, c))
	var third_area := absf(_signed_triangle_area(a, b, point))
	if absf(first_area + second_area + third_area - total_area) > 0.01:
		return false
	var safe_area := maxf(minimum_area, 0.5)
	return (
		first_area > safe_area
		and second_area > safe_area
		and third_area > safe_area
	)


func _append_unique_point(
	points: PackedVector2Array,
	point_keys: Dictionary,
	point: Vector2
) -> void:
	var key := "%d:%d" % [roundi(point.x * 100.0), roundi(point.y * 100.0)]
	if point_keys.has(key):
		return
	point_keys[key] = true
	points.append(point)


func _largest_connected_face_set(triangles: Array) -> Array:
	if triangles.is_empty():
		return []
	var edge_to_faces: Dictionary = {}
	for face_index in range(triangles.size()):
		var face: Array = triangles[face_index]
		for edge_index in range(3):
			var first := int(face[edge_index])
			var second := int(face[(edge_index + 1) % 3])
			var edge := _edge_key(first, second)
			var owners: Array = edge_to_faces.get(edge, [])
			owners.append(face_index)
			edge_to_faces[edge] = owners

	var adjacency: Array = []
	adjacency.resize(triangles.size())
	for face_index in range(triangles.size()):
		adjacency[face_index] = []
	for owners_value: Variant in edge_to_faces.values():
		var owners: Array = owners_value
		if owners.size() != 2:
			continue
		var first_owner := int(owners[0])
		var second_owner := int(owners[1])
		(adjacency[first_owner] as Array).append(second_owner)
		(adjacency[second_owner] as Array).append(first_owner)

	var visited: Dictionary = {}
	var largest_indices: Array[int] = []
	for start_index in range(triangles.size()):
		if visited.has(start_index):
			continue
		var queue: Array[int] = [start_index]
		var component: Array[int] = []
		visited[start_index] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			component.append(current)
			for neighbor_value: Variant in adjacency[current]:
				var neighbor := int(neighbor_value)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		if component.size() > largest_indices.size():
			largest_indices = component

	largest_indices.sort()
	var result: Array = []
	for face_index: int in largest_indices:
		result.append((triangles[face_index] as Array).duplicate())
	return result


func _analyze_watertight_topology(
	triangles: Array,
	outline_vertex_count: int
) -> Dictionary:
	var edge_to_faces: Dictionary = {}
	for face_index in range(triangles.size()):
		var face: Array = triangles[face_index]
		if face.size() != 3:
			return {
				"ok": false,
				"error": "Polygon topology contains a non-triangle face.",
			}
		for edge_index in range(3):
			var edge := _edge_key(
				int(face[edge_index]),
				int(face[(edge_index + 1) % 3])
			)
			var owners: Array = edge_to_faces.get(edge, [])
			owners.append(face_index)
			edge_to_faces[edge] = owners

	var expected_boundary_edges: Dictionary = {}
	for outline_index in range(outline_vertex_count):
		var next_outline_index := (outline_index + 1) % outline_vertex_count
		expected_boundary_edges[_edge_key(outline_index, next_outline_index)] = true

	var boundary_edge_count := 0
	var interior_edge_count := 0
	for edge_value: Variant in edge_to_faces:
		var edge := String(edge_value)
		var owners: Array = edge_to_faces[edge]
		if owners.size() == 1:
			if not expected_boundary_edges.has(edge):
				return {
					"ok": false,
					"error": "Polygon topology has an uncovered internal edge: %s." % edge,
				}
			boundary_edge_count += 1
		elif owners.size() == 2:
			interior_edge_count += 1
		else:
			return {
				"ok": false,
				"error": "Polygon topology has a non-manifold edge: %s." % edge,
			}
	for edge_value: Variant in expected_boundary_edges:
		var edge := String(edge_value)
		if not edge_to_faces.has(edge) or (edge_to_faces[edge] as Array).size() != 1:
			return {
				"ok": false,
				"error": "Polygon outline edge is not represented exactly once: %s." % edge,
			}
	if boundary_edge_count != outline_vertex_count:
		return {
			"ok": false,
			"error": "Polygon boundary edge count does not match its outline.",
		}
	return {
		"ok": true,
		"boundary_edge_count": boundary_edge_count,
		"interior_edge_count": interior_edge_count,
		"edge_connected_components": 1,
	}


func _build_face_records(
	image: Image,
	vertices: PackedVector2Array,
	triangles: Array,
	pivot: Vector2,
	source_bounds: Rect2,
	palette: Dictionary,
	region_guides: Dictionary,
	internal_shapes: Array
) -> Array:
	var records: Array = []
	var fallback_spine_half_width := source_bounds.size.x * float(
		region_guides.get("spine_half_width_ratio", 0.075)
	)
	for triangle_value: Variant in triangles:
		var indices: Array = triangle_value
		var a: Vector2 = vertices[int(indices[0])]
		var b: Vector2 = vertices[int(indices[1])]
		var c: Vector2 = vertices[int(indices[2])]
		var centroid := (a + b + c) / 3.0
		var area := absf((b - a).cross(c - a)) * 0.5
		var maximum_edge := maxf(
			a.distance_to(b),
			maxf(b.distance_to(c), c.distance_to(a))
		)
		var minimum_altitude := 0.0
		if maximum_edge > 0.0:
			minimum_altitude = area * 2.0 / maximum_edge
		var sampled_color := _sample_triangle_color(image, a, b, c)
		var palette_role := _nearest_palette_role(sampled_color, palette)
		var local_x := centroid.x - pivot.x
		var region := String(region_guides.get("spine_region", "spine"))
		var internal_shape := _internal_shape_for_point(
			centroid,
			internal_shapes
		)
		if not internal_shape.is_empty():
			region = String(internal_shape["region"])
			palette_role = String(internal_shape["palette_role"])
		elif internal_shapes.is_empty():
			if local_x < -fallback_spine_half_width:
				region = String(region_guides.get("left_region", "left_page"))
			elif local_x > fallback_spine_half_width:
				region = String(region_guides.get("right_region", "right_page"))
		elif centroid.x < float((internal_shapes[0] as Dictionary)["left_x"]):
			region = String(region_guides.get("left_region", "left_page"))
		else:
			region = String(region_guides.get("right_region", "right_page"))
		var surface_kind := _surface_kind_for_palette_role(palette_role)
		records.append({
			"indices": [int(indices[0]), int(indices[1]), int(indices[2])],
			"palette_role": palette_role,
			"surface_kind": surface_kind,
			"region": region,
			"clear_order": 1.0,
			"_centroid_x": local_x,
			"_centroid_y": centroid.y - pivot.y,
			"_area": area,
			"_minimum_altitude": minimum_altitude,
		})
	return records


func _internal_shape_for_point(
	point: Vector2,
	internal_shapes: Array
) -> Dictionary:
	for shape_value: Variant in internal_shapes:
		var shape: Dictionary = shape_value
		if (
			String(shape.get("kind", "")) == "vertical_band"
			and point.x >= float(shape["left_x"]) - 0.0001
			and point.x <= float(shape["right_x"]) + 0.0001
		):
			return shape
	return {}


func _surface_kind_for_palette_role(role: String) -> String:
	if role.begins_with("cover_"):
		return "cover"
	if role.begins_with("page_") or role == "accent_warm":
		return "page"
	return role


func _apply_facet_emphasis(
	records: Array,
	guides_value: Variant,
	source_bounds: Rect2,
	pivot: Vector2,
	palette: Dictionary
) -> Dictionary:
	if not guides_value is Array:
		return _failure("Manifest facet_emphasis must be an array.")
	var guides: Array = guides_value
	var applied_count := 0
	for guide_value: Variant in guides:
		if not guide_value is Dictionary:
			return _failure("Manifest facet_emphasis entries must be dictionaries.")
		var guide: Dictionary = guide_value
		var palette_role := String(guide.get("palette_role", ""))
		if not palette.has(palette_role) or palette_role == "outline":
			return _failure("Facet emphasis palette_role is invalid.")
		var position_value: Variant = guide.get("normalized_position", [])
		if not position_value is Array or (position_value as Array).size() != 2:
			return _failure("Facet emphasis normalized_position is invalid.")
		var normalized_position := _array_to_vector2(position_value)
		if (
			normalized_position.x < 0.0
			or normalized_position.x > 1.0
			or normalized_position.y < 0.0
			or normalized_position.y > 1.0
		):
			return _failure("Facet emphasis normalized_position is outside 0..1.")
		var target := (
			source_bounds.position
			+ source_bounds.size * normalized_position
			- pivot
		)
		var required_region := String(guide.get("region", ""))
		var minimum_area := maxf(float(guide.get("minimum_area_px2", 0.0)), 0.0)
		var best_index := -1
		var best_distance := INF
		for record_index in range(records.size()):
			var record: Dictionary = records[record_index]
			if (
				not required_region.is_empty()
				and String(record.get("region", "")) != required_region
			):
				continue
			if float(record.get("_area", 0.0)) < minimum_area:
				continue
			var centroid := Vector2(
				float(record.get("_centroid_x", 0.0)),
				float(record.get("_centroid_y", 0.0))
			)
			var distance := centroid.distance_squared_to(target)
			if distance < best_distance:
				best_distance = distance
				best_index = record_index
		if best_index < 0:
			return _failure("Facet emphasis could not find a matching face.")
		var emphasized_record: Dictionary = records[best_index]
		emphasized_record["palette_role"] = palette_role
		applied_count += 1
	return {"ok": true, "count": applied_count}


func _assign_clear_order(records: Array) -> void:
	records.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_distance := absf(float(first["_centroid_x"]))
		var second_distance := absf(float(second["_centroid_x"]))
		if not is_equal_approx(first_distance, second_distance):
			return first_distance > second_distance
		if not is_equal_approx(float(first["_centroid_y"]), float(second["_centroid_y"])):
			return float(first["_centroid_y"]) < float(second["_centroid_y"])
		return String(first["region"]) < String(second["region"])
	)
	for index in range(records.size()):
		var record: Dictionary = records[index]
		record["clear_order"] = float(index + 1) / float(records.size())
		record.erase("_centroid_x")
		record.erase("_centroid_y")
		record.erase("_area")
		record.erase("_minimum_altitude")


func _build_anchors(manifest: Dictionary, bounds: Rect2) -> Dictionary:
	var anchor_guides: Dictionary = manifest.get("anchors", {})
	var anchors: Dictionary = {}
	for anchor_name: String in anchor_guides:
		var normalized := _array_to_vector2(anchor_guides[anchor_name])
		var local_point := bounds.position + Vector2(
			bounds.size.x * normalized.x,
			bounds.size.y * normalized.y
		)
		anchors[anchor_name] = _vector2_to_array(local_point)
	return anchors


func _count_regions(records: Array) -> Dictionary:
	var counts: Dictionary = {}
	for record_value: Variant in records:
		var record: Dictionary = record_value
		var region := String(record.get("region", ""))
		counts[region] = int(counts.get(region, 0)) + 1
	return counts


func _sample_triangle_color(image: Image, a: Vector2, b: Vector2, c: Vector2) -> Color:
	var sample_points := [
		(a + b + c) / 3.0,
		(a + b) * 0.5,
		(b + c) * 0.5,
		(c + a) * 0.5,
	]
	var sum := Vector3.ZERO
	for point: Vector2 in sample_points:
		var x := clampi(roundi(point.x), 0, image.get_width() - 1)
		var y := clampi(roundi(point.y), 0, image.get_height() - 1)
		var color := image.get_pixel(x, y)
		sum += Vector3(color.r, color.g, color.b)
	sum /= float(sample_points.size())
	return Color(sum.x, sum.y, sum.z)


func _nearest_palette_role(color: Color, palette: Dictionary) -> String:
	var best_role := ""
	var best_distance := INF
	for role: String in palette:
		if role == "outline":
			continue
		var palette_color: Color = palette[role]
		var delta := Vector3(
			color.r - palette_color.r,
			color.g - palette_color.g,
			color.b - palette_color.b
		)
		var distance := delta.length_squared()
		if distance < best_distance:
			best_distance = distance
			best_role = role
	return best_role


func _parse_palette(style: Dictionary) -> Dictionary:
	var palette_value: Variant = style.get("palette", {})
	if not palette_value is Dictionary:
		return _failure("Style Profile palette is missing.")
	var palette_source: Dictionary = palette_value
	var palette: Dictionary = {}
	for role: String in palette_source:
		var html := String(palette_source[role])
		if not html.is_valid_html_color():
			return _failure("Invalid palette color for role %s." % role)
		palette[role] = Color(html)
	if not palette.has("outline") or palette.size() < 2:
		return _failure("Style Profile palette needs outline and fill colors.")
	return {"ok": true, "palette": palette}


func _build_foreground_mask(image: Image, key_color: Color, threshold: float) -> BitMap:
	var mask := BitMap.new()
	mask.create(Vector2i(image.get_size()))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			var delta := Vector3(
				color.r - key_color.r,
				color.g - key_color.g,
				color.b - key_color.b
			)
			mask.set_bit(x, y, delta.length() > threshold)
	return mask


func _extract_largest_outline(mask: BitMap, epsilon: float) -> Dictionary:
	var polygons := mask.opaque_to_polygons(
		Rect2i(Vector2i.ZERO, mask.get_size()),
		epsilon
	)
	if polygons.is_empty():
		return _failure("BitMap marching squares found no foreground outline.")
	var largest := PackedVector2Array()
	var largest_area := 0.0
	for polygon_value: Variant in polygons:
		var polygon: PackedVector2Array = polygon_value
		var area := absf(_polygon_signed_area(polygon))
		if area > largest_area:
			largest_area = area
			largest = polygon
	if largest.size() < 3:
		return _failure("Largest foreground outline has fewer than three points.")
	return {"ok": true, "outline": largest}


func _point_is_foreground(
	point: Vector2,
	mask: BitMap,
	outline: PackedVector2Array
) -> bool:
	if not Geometry2D.is_point_in_polygon(point, outline):
		return false
	var x := clampi(floori(point.x), 0, mask.get_size().x - 1)
	var y := clampi(floori(point.y), 0, mask.get_size().y - 1)
	return mask.get_bit(x, y)


func _polygon_signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _signed_triangle_area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b - a).cross(c - a) * 0.5


func _bounds_for_points(points: PackedVector2Array) -> Rect2:
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _edge_key(first: int, second: int) -> String:
	return "%d:%d" % [mini(first, second), maxi(first, second)]


func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(65_536))
	return context.finish().hex_encode()


func _load_image(path: String) -> Dictionary:
	if path.is_empty():
		return _failure("Source image path is empty.")
	var image := Image.new()
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := image.load(absolute_path)
	if error != OK:
		return _failure("Failed to load source image: %s" % error_string(error))
	return {"ok": true, "image": image}


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _failure("JSON file does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Failed to open JSON file: %s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		return _failure(
			"Invalid JSON object at %s:%d: %s"
			% [path, parser.get_error_line(), parser.get_error_message()]
		)
	return {"ok": true, "data": (parser.data as Dictionary).duplicate(true)}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _array_to_vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	var values: Array = value
	return Vector2(float(values[0]), float(values[1]))


func _array_to_vector2i(value: Variant) -> Vector2i:
	var vector := _array_to_vector2(value)
	return Vector2i(roundi(vector.x), roundi(vector.y))


func _vector2_to_array(value: Vector2) -> Array:
	return [_round_number(value.x), _round_number(value.y)]


func _vector2i_to_array(value: Vector2i) -> Array:
	return [value.x, value.y]


func _packed_vector2_to_arrays(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append(_vector2_to_array(point))
	return result


func _rect_to_dictionary(rect: Rect2) -> Dictionary:
	return {
		"min": _vector2_to_array(rect.position),
		"max": _vector2_to_array(rect.end),
		"size": _vector2_to_array(rect.size),
	}


func _round_number(value: float) -> float:
	return snappedf(value, 0.001)
