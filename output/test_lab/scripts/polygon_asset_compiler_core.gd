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
	var outline: PackedVector2Array = outline_result["outline"]
	var source_bounds := _bounds_for_points(outline)

	var triangulation_result := _triangulate_with_target(
		image,
		mask,
		outline,
		style
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
	for point: Vector2 in outline:
		local_outline.append(point - pivot)

	var palette_result := _parse_palette(style)
	if not palette_result["ok"]:
		return palette_result
	var palette: Dictionary = palette_result["palette"]
	var region_guides: Dictionary = manifest.get("region_guides", {})
	var spine_half_width := source_bounds.size.x * float(
		region_guides.get("spine_half_width_ratio", 0.075)
	)
	var face_records := _build_face_records(
		image,
		vertices,
		triangles,
		pivot,
		spine_half_width,
		palette,
		region_guides
	)
	if face_records.is_empty():
		return _failure("No valid polygon faces remained after palette assignment.")
	var minimum_visible_altitude := float(
		style.get("minimum_visible_face_altitude_px", 4.0)
	)
	if minimum_visible_altitude <= 0.0:
		return _failure("Style Profile minimum_visible_face_altitude_px is invalid.")
	var visually_merged_face_count := _merge_skinny_face_palette_roles(
		face_records,
		minimum_visible_altitude
	)
	var minimum_visible_color_region_area := float(
		style.get("minimum_visible_color_region_area_px2", 0.0)
	)
	if minimum_visible_color_region_area <= 0.0:
		return _failure(
			"Style Profile minimum_visible_color_region_area_px2 is invalid."
		)
	var emphasis_result := _apply_facet_emphasis(
		face_records,
		manifest.get("facet_emphasis", []),
		source_bounds,
		pivot,
		palette
	)
	if not bool(emphasis_result.get("ok", false)):
		return emphasis_result
	var visually_merged_small_region_face_count := _merge_small_color_regions(
		face_records,
		vertices,
		minimum_visible_color_region_area
	)
	_assign_clear_order(face_records)

	var local_bounds := Rect2(source_bounds.position - pivot, source_bounds.size)
	var collision_points := Geometry2D.convex_hull(local_outline)
	if collision_points.size() > 1 and collision_points[0].is_equal_approx(
		collision_points[collision_points.size() - 1]
	):
		collision_points.remove_at(collision_points.size() - 1)
	var anchors := _build_anchors(manifest, local_bounds)
	var region_counts := _count_regions(face_records)

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
			"sample_spacing_px": actual_spacing,
			"minimum_triangle_area_px2": float(
				triangulation_result["minimum_triangle_area_px2"]
			),
			"minimum_visible_face_altitude_px": minimum_visible_altitude,
			"minimum_visible_color_region_area_px2":
				minimum_visible_color_region_area,
			"visually_merged_skinny_face_count": visually_merged_face_count,
			"visually_merged_small_region_face_count":
				visually_merged_small_region_face_count,
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


func _triangulate_with_target(
	image: Image,
	mask: BitMap,
	outline: PackedVector2Array,
	style: Dictionary
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
			target_min
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
	minimum_face_count: int
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
			if area <= minimum_area:
				return _failure(
					"Constrained Delaunay produced a triangle below the minimum area."
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
		for face_index in range(connected.size()):
			var face: Array = connected[face_index]
			var face_area := absf(_signed_triangle_area(
				output_points[int(face[0])],
				output_points[int(face[1])],
				output_points[int(face[2])]
			))
			if face_area > largest_face_area:
				largest_face_area = face_area
				largest_face_index = face_index
		if largest_face_index < 0 or largest_face_area <= minimum_area * 3.2:
			return _failure("Unable to reach the minimum face target without tiny triangles.")
		var largest_face: Array = connected[largest_face_index]
		var split_point := (
			output_points[int(largest_face[0])]
			+ output_points[int(largest_face[1])]
			+ output_points[int(largest_face[2])]
		) / 3.0
		var split_index := output_points.size()
		output_points.append(split_point)
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
	for face_value: Variant in connected:
		var face: Array = face_value
		minimum_found = minf(
			minimum_found,
			absf(_signed_triangle_area(
				output_points[int(face[0])],
				output_points[int(face[1])],
				output_points[int(face[2])]
			))
		)
	return {
		"ok": true,
		"vertices": output_points,
		"triangles": connected,
		"minimum_triangle_area_px2": minimum_found,
		"topology": topology,
	}


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
	spine_half_width: float,
	palette: Dictionary,
	region_guides: Dictionary
) -> Array:
	var records: Array = []
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
		var palette_family := _palette_family(palette_role)
		var local_x := centroid.x - pivot.x
		var region := String(region_guides.get("spine_region", "spine"))
		if local_x < -spine_half_width:
			region = String(region_guides.get("left_region", "left_page"))
		elif local_x > spine_half_width:
			region = String(region_guides.get("right_region", "right_page"))
		records.append({
			"indices": [int(indices[0]), int(indices[1]), int(indices[2])],
			"palette_role": palette_role,
			"surface_kind": palette_family,
			"region": region,
			"clear_order": 1.0,
			"_centroid_x": local_x,
			"_centroid_y": centroid.y - pivot.y,
			"_area": area,
			"_minimum_altitude": minimum_altitude,
			"_palette_family": palette_family,
		})
	return records


func _merge_skinny_face_palette_roles(
	records: Array,
	minimum_visible_altitude: float
) -> int:
	var skinny_face_indices: Array[int] = []
	for face_index in range(records.size()):
		var record: Dictionary = records[face_index]
		if float(record.get("_minimum_altitude", 0.0)) >= minimum_visible_altitude:
			continue
		skinny_face_indices.append(face_index)
	for _pass_index in range(records.size()):
		var changed := false
		for face_index: int in skinny_face_indices:
			var record: Dictionary = records[face_index]
			var neighbor_index := _best_visual_merge_neighbor(
				records,
				face_index,
				minimum_visible_altitude
			)
			if neighbor_index < 0:
				continue
			var neighbor: Dictionary = records[neighbor_index]
			var inherited_role := String(neighbor.get("palette_role", ""))
			if String(record.get("palette_role", "")) == inherited_role:
				continue
			record["palette_role"] = inherited_role
			changed = true
		if not changed:
			break
	return skinny_face_indices.size()


func _merge_small_color_regions(
	records: Array,
	vertices: PackedVector2Array,
	minimum_region_area: float
) -> int:
	var changed_face_indices: Dictionary = {}
	for _pass_index in range(records.size()):
		var components := _build_color_components(records)
		var selected_component: Dictionary = {}
		var selected_area := INF
		var selected_first_index := records.size()
		for component_value: Variant in components:
			var component: Dictionary = component_value
			var component_area := float(component.get("area", 0.0))
			var component_first_index := int(component.get("first_index", records.size()))
			if component_area >= minimum_region_area:
				continue
			if (
				component_area < selected_area
				or (
					is_equal_approx(component_area, selected_area)
					and component_first_index < selected_first_index
				)
			):
				selected_component = component
				selected_area = component_area
				selected_first_index = component_first_index
		if selected_component.is_empty():
			break
		var component_indices: Array = selected_component.get("indices", [])
		var target_role := _best_color_region_merge_role(
			records,
			vertices,
			component_indices
		)
		if target_role.is_empty():
			break
		for face_index_value: Variant in component_indices:
			var face_index := int(face_index_value)
			var record: Dictionary = records[face_index]
			record["palette_role"] = target_role
			changed_face_indices[face_index] = true
	return changed_face_indices.size()


func _build_color_components(records: Array) -> Array:
	var visited: Dictionary = {}
	var components: Array = []
	for start_index in range(records.size()):
		if visited.has(start_index):
			continue
		var role := String((records[start_index] as Dictionary).get(
			"palette_role",
			""
		))
		var queue: Array[int] = [start_index]
		var component_indices: Array[int] = []
		var component_area := 0.0
		visited[start_index] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			component_indices.append(current)
			var current_record: Dictionary = records[current]
			component_area += float(current_record.get("_area", 0.0))
			for neighbor_index in range(records.size()):
				if visited.has(neighbor_index):
					continue
				var neighbor: Dictionary = records[neighbor_index]
				if String(neighbor.get("palette_role", "")) != role:
					continue
				if not _records_share_edge(current_record, neighbor):
					continue
				visited[neighbor_index] = true
				queue.append(neighbor_index)
		component_indices.sort()
		components.append({
			"indices": component_indices,
			"area": component_area,
			"first_index": component_indices[0],
		})
	return components


func _best_color_region_merge_role(
	records: Array,
	vertices: PackedVector2Array,
	component_indices: Array
) -> String:
	var component_lookup: Dictionary = {}
	for face_index_value: Variant in component_indices:
		component_lookup[int(face_index_value)] = true
	var boundary_lengths: Dictionary = {}
	for face_index_value: Variant in component_indices:
		var face_index := int(face_index_value)
		var face: Dictionary = records[face_index]
		for neighbor_index in range(records.size()):
			if component_lookup.has(neighbor_index):
				continue
			var neighbor: Dictionary = records[neighbor_index]
			if not _records_share_edge(face, neighbor):
				continue
			var neighbor_role := String(neighbor.get("palette_role", ""))
			boundary_lengths[neighbor_role] = (
				float(boundary_lengths.get(neighbor_role, 0.0))
				+ _shared_record_edge_length(face, neighbor, vertices)
			)
	var best_role := ""
	var best_boundary_length := -1.0
	for role_value: Variant in boundary_lengths:
		var role := String(role_value)
		var boundary_length := float(boundary_lengths[role])
		if boundary_length > best_boundary_length:
			best_role = role
			best_boundary_length = boundary_length
	return best_role


func _shared_record_edge_length(
	first: Dictionary,
	second: Dictionary,
	vertices: PackedVector2Array
) -> float:
	var shared_indices: Array[int] = []
	var first_indices: Array = first.get("indices", [])
	var second_indices: Array = second.get("indices", [])
	for first_index_value: Variant in first_indices:
		if second_indices.has(first_index_value):
			shared_indices.append(int(first_index_value))
	if shared_indices.size() != 2:
		return 0.0
	return vertices[shared_indices[0]].distance_to(vertices[shared_indices[1]])


func _best_visual_merge_neighbor(
	records: Array,
	face_index: int,
	minimum_visible_altitude: float
) -> int:
	var source: Dictionary = records[face_index]
	var source_region := String(source.get("region", ""))
	var source_family := String(source.get("_palette_family", ""))
	var has_same_family_candidate := false
	for candidate_index in range(records.size()):
		if candidate_index == face_index:
			continue
		var candidate: Dictionary = records[candidate_index]
		var is_major := (
			float(candidate.get("_minimum_altitude", 0.0))
			>= minimum_visible_altitude
		)
		if (
			not _records_share_edge(source, candidate)
			and not _records_share_vertex(source, candidate)
			and not is_major
		):
			continue
		if (
			String(candidate.get("_palette_family", "")) == source_family
		):
			has_same_family_candidate = true
			break
	var best_index := -1
	var best_score := -INF
	for candidate_index in range(records.size()):
		if candidate_index == face_index:
			continue
		var candidate: Dictionary = records[candidate_index]
		var shares_edge := _records_share_edge(source, candidate)
		var shares_vertex := _records_share_vertex(source, candidate)
		var is_major := (
			float(candidate.get("_minimum_altitude", 0.0))
			>= minimum_visible_altitude
		)
		var same_family := (
			String(candidate.get("_palette_family", "")) == source_family
		)
		if not shares_edge and not shares_vertex and not (is_major and same_family):
			continue
		if (
			has_same_family_candidate
			and not same_family
		):
			continue
		var score := float(candidate.get("_area", 0.0))
		if is_major:
			score += 1_000_000_000.0
		if String(candidate.get("region", "")) == source_region:
			score += 100_000_000.0
		if same_family:
			score += 10_000_000.0
		if shares_edge:
			score += 1_000_000.0
		elif shares_vertex:
			score += 500_000.0
		var source_centroid := Vector2(
			float(source.get("_centroid_x", 0.0)),
			float(source.get("_centroid_y", 0.0))
		)
		var candidate_centroid := Vector2(
			float(candidate.get("_centroid_x", 0.0)),
			float(candidate.get("_centroid_y", 0.0))
		)
		score -= source_centroid.distance_squared_to(candidate_centroid)
		if score > best_score:
			best_score = score
			best_index = candidate_index
	return best_index


func _records_share_edge(first: Dictionary, second: Dictionary) -> bool:
	var first_indices: Array = first.get("indices", [])
	var second_indices: Array = second.get("indices", [])
	var shared_count := 0
	for first_index_value: Variant in first_indices:
		if second_indices.has(int(first_index_value)):
			shared_count += 1
	return shared_count >= 2


func _records_share_vertex(first: Dictionary, second: Dictionary) -> bool:
	var first_indices: Array = first.get("indices", [])
	var second_indices: Array = second.get("indices", [])
	for first_index_value: Variant in first_indices:
		if second_indices.has(int(first_index_value)):
			return true
	return false


func _palette_family(role: String) -> String:
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
		record.erase("_palette_family")


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
