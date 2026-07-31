extends SceneTree

const ASSET_PATH: String = (
	"res://data/polygon_assets/apple.polygon.json"
)
const COMPILER := preload(
	"res://scripts/polygon_asset_compiler_core.gd"
)
const COMPILER_SOURCE_PATH: String = (
	"res://scripts/polygon_asset_compiler_core.gd"
)
const MANIFEST_PATH: String = (
	"res://data/polygon_imports/apple.json"
)
const PROMPT_BUILDER := preload(
	"res://scripts/polygon_prompt_builder.gd"
)
const RUNTIME_SCRIPT := preload(
	"res://scripts/polygon_asset_2d.gd"
)
const SCENE_PATH: String = (
	"res://scenes/polygon_apple_test.tscn"
)
const SILHOUETTE_TEMPLATE_PATH: String = (
	"res://data/polygon_imports/_silhouette_asset.template.json"
)
const SOURCE_PATH: String = (
	"res://assets/polygon_art/apple_source.png"
)
const STYLE_PATH: String = "res://data/polygon_art_style.json"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var compiler := COMPILER.new()
	var first_result: Dictionary = compiler.compile_manifest(
		MANIFEST_PATH
	)
	var second_result: Dictionary = compiler.compile_manifest(
		MANIFEST_PATH
	)
	_check(
		bool(first_result.get("ok", false)),
		"Apple manifest compilation succeeds."
	)
	_check(
		bool(second_result.get("ok", false)),
		"Repeated apple manifest compilation succeeds."
	)
	if (
		not bool(first_result.get("ok", false))
		or not bool(second_result.get("ok", false))
	):
		_finish()
		return
	var first_data: Dictionary = first_result["data"]
	var second_data: Dictionary = second_result["data"]
	_check(
		JSON.stringify(first_data, "", true, true)
		== JSON.stringify(second_data, "", true, true),
		"Apple manifest compilation is deterministic."
	)

	var checked_in_result := _load_json_dictionary(ASSET_PATH)
	_check(
		bool(checked_in_result.get("ok", false)),
		"Checked-in apple Polygon JSON loads."
	)
	if not bool(checked_in_result.get("ok", false)):
		_finish()
		return
	var asset_data: Dictionary = checked_in_result["data"]
	_check(
		_variants_equivalent(first_data, asset_data),
		"Checked-in apple JSON matches a fresh compile."
	)

	_validate_generic_sources()
	_validate_prompt()
	_validate_source(asset_data)
	_validate_asset(asset_data)
	await _validate_runtime()
	await _validate_scene()
	_finish()


func _validate_generic_sources() -> void:
	var compiler_file := FileAccess.open(
		COMPILER_SOURCE_PATH,
		FileAccess.READ
	)
	_check(
		compiler_file != null,
		"Generic Polygon compiler source is readable."
	)
	if compiler_file != null:
		var compiler_source := compiler_file.get_as_text()
		_check(
			compiler_source.find("apple") < 0,
			"Generic compiler contains no apple-specific branch."
		)
		_check(
			compiler_source.contains("guides.size() > 1"),
			"Generic compiler supports an optional primary feature."
		)
	var silhouette_template_result := _load_json_dictionary(
		SILHOUETTE_TEMPLATE_PATH
	)
	_check(
		bool(silhouette_template_result.get("ok", false)),
		"Reusable silhouette-only manifest template loads."
	)
	if bool(silhouette_template_result.get("ok", false)):
		var silhouette_template: Dictionary = (
			silhouette_template_result["data"]
		)
		_check(
			(silhouette_template.get("feature_guides", []) as Array).is_empty()
			and silhouette_template.get("palette", {}) is Dictionary
			and silhouette_template.get("custom_animation", {}) is Dictionary,
			"Silhouette template declares no landmark and no semantic adapter."
		)


func _validate_prompt() -> void:
	var builder := PROMPT_BUILDER.new()
	var first_prompt: Dictionary = builder.build_from_manifest(
		MANIFEST_PATH
	)
	var second_prompt: Dictionary = builder.build_from_manifest(
		MANIFEST_PATH
	)
	_check(
		bool(first_prompt.get("ok", false)),
		"Apple manifest renders through the reusable prompt template."
	)
	_check(
		JSON.stringify(first_prompt, "", true, true)
		== JSON.stringify(second_prompt, "", true, true),
		"Apple prompt rendering is deterministic."
	)
	if not bool(first_prompt.get("ok", false)):
		return
	var prompt := String(first_prompt.get("prompt", ""))
	_check(
		prompt.contains("No internal structural landmark is required")
		and prompt.contains("whole red apple")
		and not prompt.contains("Landmark 1"),
		"Apple prompt uses silhouette-only authoring instructions."
	)


func _validate_source(asset_data: Dictionary) -> void:
	var image := Image.new()
	var load_error := image.load(
		ProjectSettings.globalize_path(SOURCE_PATH)
	)
	_check(load_error == OK, "Apple source PNG decodes without import cache.")
	if load_error != OK:
		return
	var border_is_keyed := true
	var expected_key := Color("#ff00ff")
	for x in range(image.get_width()):
		border_is_keyed = (
			border_is_keyed
			and image.get_pixel(x, 0).is_equal_approx(expected_key)
			and image.get_pixel(
				x,
				image.get_height() - 1
			).is_equal_approx(expected_key)
		)
	for y in range(image.get_height()):
		border_is_keyed = (
			border_is_keyed
			and image.get_pixel(0, y).is_equal_approx(expected_key)
			and image.get_pixel(
				image.get_width() - 1,
				y
			).is_equal_approx(expected_key)
		)
	_check(border_is_keyed, "Apple source PNG border is exact #ff00ff.")
	var source: Dictionary = asset_data.get("source", {})
	_check(
		String(source.get("sha256", ""))
		== FileAccess.get_sha256(SOURCE_PATH),
		"Apple Polygon JSON source hash matches the source PNG."
	)


func _validate_asset(asset_data: Dictionary) -> void:
	var manifest_result := _load_json_dictionary(MANIFEST_PATH)
	_check(
		bool(manifest_result.get("ok", false)),
		"Apple import manifest loads."
	)
	if not bool(manifest_result.get("ok", false)):
		return
	var manifest: Dictionary = manifest_result["data"]
	var palette: Dictionary = asset_data.get("palette", {})
	_check(
		palette == manifest.get("palette", {}),
		"Compiled apple keeps the manifest-owned palette."
	)
	var style_result := _load_json_dictionary(STYLE_PATH)
	if bool(style_result.get("ok", false)):
		_check(
			palette != (style_result["data"] as Dictionary).get(
				"palette",
				{}
			),
			"Per-asset palette overrides the book-colored Style fallback."
		)
	_check(
		int(asset_data.get("schema_version", 0)) == 3,
		"Apple Polygon asset uses schema v3."
	)
	_check(
		String(asset_data.get("asset_id", "")) == "apple",
		"Apple asset id is stable."
	)
	var features: Array = asset_data.get("features", [])
	var stats: Dictionary = asset_data.get("stats", {})
	_check(
		features.is_empty()
		and int(stats.get("feature_count", -1)) == 0
		and int(stats.get("protected_feature_edge_count", -1)) == 0,
		"Apple compiles without a fabricated landmark band."
	)
	var construction: Dictionary = asset_data.get("construction", {})
	_check(
		construction.get("source_usage", [])
		== ["outer_shape", "color_reference"]
		and String(asset_data.get("clear_order", "")) == "top_to_bottom",
		"Silhouette-only construction records its actual source usage."
	)
	_check(
		(asset_data.get("custom_animation", {}) as Dictionary).is_empty(),
		"Apple declares no semantic animation adapter."
	)
	var regions: Dictionary = asset_data.get("regions", {})
	_check(
		regions.size() == 1 and regions.has("apple"),
		"Apple uses one manifest-defined semantic region."
	)
	var motion_profile: Dictionary = asset_data.get(
		"motion_profile",
		{}
	)
	_check(
		motion_profile.get("primary_motion_regions", []) == ["apple"]
		and (
			motion_profile.get("motion_surface_kinds", []) as Array
		).has("fruit")
		and (
			motion_profile.get("motion_surface_kinds", []) as Array
		).has("leaf"),
		"Apple binds generic motion through manifest regions and surface kinds."
	)

	var vertices := _vector2_array_from_json(
		asset_data.get("vertices", [])
	)
	var faces: Array = asset_data.get("faces", [])
	var target_config: Dictionary = (
		(style_result.get("data", {}) as Dictionary).get(
			"target_face_count",
			{}
		)
	)
	_check(
		faces.size() >= int(target_config.get("min", 48))
		and faces.size() <= int(target_config.get("max", 80)),
		"Apple face count stays inside the Style Profile target."
	)
	var faces_are_valid := true
	for face_value: Variant in faces:
		if not face_value is Dictionary:
			faces_are_valid = false
			continue
		var face: Dictionary = face_value
		var indices_value: Variant = face.get("indices", [])
		if not indices_value is Array or (indices_value as Array).size() != 3:
			faces_are_valid = false
			continue
		var indices: Array = indices_value
		for index_value: Variant in indices:
			var vertex_index := int(index_value)
			faces_are_valid = (
				faces_are_valid
				and vertex_index >= 0
				and vertex_index < vertices.size()
			)
		if not faces_are_valid:
			continue
		var area := absf(
			(vertices[int(indices[1])] - vertices[int(indices[0])]).cross(
				vertices[int(indices[2])] - vertices[int(indices[0])]
			)
		) * 0.5
		faces_are_valid = (
			faces_are_valid
			and area >= float(
				stats.get("minimum_visible_face_area_px2", 0.0)
			)
			and palette.has(String(face.get("palette_role", "")))
			and String(face.get("region", "")) == "apple"
		)
	_check(
		faces_are_valid,
		"Apple faces are indexed, visible, colored, and region-valid."
	)
	_check(
		int(stats.get("connected_components", 0)) == 1
		and bool(stats.get("watertight", false))
		and int(stats.get("draw_surfaces", 0)) == 1,
		"Apple mesh is one watertight connected component and one surface."
	)
	var anchors: Dictionary = asset_data.get("anchors", {})
	_check(
		anchors.has("center")
		and anchors.has("stem")
		and anchors.has("interaction"),
		"Apple exposes center, stem, and interaction anchors."
	)


func _validate_runtime() -> void:
	var runtime := RUNTIME_SCRIPT.new()
	runtime.name = "AppleRuntimeUnderTest"
	root.add_child(runtime)
	var load_error: Error = runtime.load_asset(ASSET_PATH)
	_check(load_error == OK, "Generic runtime loads the apple Polygon asset.")
	if load_error != OK:
		runtime.queue_free()
		await process_frame
		return
	var runtime_stats: Dictionary = runtime.get_runtime_stats()
	var mesh_instance := runtime.get_mesh_instance()
	var mesh := mesh_instance.mesh as ArrayMesh
	var material := mesh_instance.material as ShaderMaterial
	var generic_shader := load(
		"res://shaders/polygon_asset.gdshader"
	) as Shader
	_check(
		mesh != null
		and mesh.get_surface_count() == 1
		and mesh_instance.texture == null,
		"Apple runtime uses one texture-free ArrayMesh surface."
	)
	_check(
		material != null
		and material.shader
		== generic_shader,
		"Apple runtime stays on the generic effect shader."
	)
	_check(
		int(runtime_stats.get("primary_motion_face_count", 0)) > 0,
		"Apple exposes manifest-authored generic motion faces."
	)
	_check(
		int(runtime_stats.get("pinned_outline_vertex_count", 0)) > 0
		and int(runtime_stats.get("motion_logical_vertex_count", 0)) > 0,
		"Apple retains semantic masks while velocity deformation owns the full silhouette."
	)
	runtime.set_movement_velocity(Vector2(90.0, 0.0), 100.0)
	runtime.set_generation_progress(0.35)
	runtime.set_dissolve_progress(0.45)
	var target_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		_array_to_vector2(
			target_stats.get("movement_target_direction", [])
		).is_equal_approx(Vector2.RIGHT)
		and is_equal_approx(
			float(target_stats.get("movement_target_amount", 0.0)),
			0.9
		)
		and is_zero_approx(
			float(target_stats.get("movement_amount", -1.0))
		),
		"Apple converts gameplay velocity into a deformation target."
	)
	runtime.advance_movement_deformation(0.08)
	var response_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		_array_to_vector2(
			response_stats.get("movement_direction", [])
		).is_equal_approx(Vector2.RIGHT)
		and float(response_stats.get("movement_amount", 0.0)) > 0.0
		and float(response_stats.get("movement_amount", 0.0)) < 0.9
		and float(
			response_stats.get("movement_spring_speed", 0.0)
		) > 0.0,
		"Movement deformation follows velocity through a damped spring instead of snapping."
	)
	_check(
		is_equal_approx(
			float(response_stats.get("generation_progress", 0.0)),
			0.35
		)
		and is_equal_approx(
			float(response_stats.get("dissolve_progress", 0.0)),
			0.45
		),
		"Spring movement remains independent from lifecycle progress."
	)
	runtime.set_movement_velocity(Vector2.ZERO, 100.0)
	var moving_amount := float(
		runtime.get_runtime_stats().get("movement_amount", 0.0)
	)
	runtime.advance_movement_deformation(0.05)
	var stopping_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		_array_to_vector2(
			stopping_stats.get("movement_target_direction", [])
		).is_zero_approx()
		and float(stopping_stats.get("movement_amount", 0.0)) > 0.0
		and not is_equal_approx(
			float(stopping_stats.get("movement_amount", 0.0)),
			moving_amount
		),
		"Stopping keeps a short inertial tail instead of snapping rigid."
	)
	for _step_index in range(30):
		runtime.advance_movement_deformation(0.1)
	var settled_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		is_zero_approx(
			float(settled_stats.get("movement_amount", -1.0))
		)
		and is_zero_approx(
			float(settled_stats.get("movement_spring_speed", -1.0))
		),
		"Damped movement settles to an exact non-breathing rest state."
	)
	runtime.set_movement_state(Vector2.UP, 0.65)
	var upward_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		_array_to_vector2(
			upward_stats.get("movement_direction", [])
		).is_equal_approx(Vector2.UP)
		and is_equal_approx(
			float(upward_stats.get("movement_amount", 0.0)),
			0.65
		),
		"Cardinal movement deformation is directly controllable."
	)
	runtime.reset_visual()
	var reset_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		is_equal_approx(
			float(reset_stats.get("generation_progress", 0.0)),
			1.0
		)
		and is_zero_approx(
			float(reset_stats.get("dissolve_progress", -1.0))
		)
		and _array_to_vector2(
			reset_stats.get("movement_direction", [])
		).is_zero_approx()
		and is_zero_approx(
			float(reset_stats.get("movement_amount", -1.0))
		),
		"Apple generic animation reset restores a complete visible asset."
	)
	runtime.queue_free()
	await process_frame


func _validate_scene() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_check(packed_scene != null, "Polygon apple demo scene loads.")
	if packed_scene == null:
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	_check(
		scene.has_method("prepare_capture")
		and scene.has_method("get_auto_demo_state")
		and scene.has_method("debug_set_auto_demo_time"),
		"Apple demo exposes deterministic generic animation controls."
	)
	if not scene.has_method("debug_set_auto_demo_time"):
		scene.queue_free()
		await process_frame
		return
	scene.call("debug_set_auto_demo_time", 0.45)
	var polygon_asset: Node = scene.call("get_polygon_asset")
	var generation_stats: Dictionary = polygon_asset.call(
		"get_runtime_stats"
	)
	_check(
		float(generation_stats.get("generation_progress", 1.0)) > 0.3
		and float(
			generation_stats.get("generation_progress", 1.0)
		) < 0.7,
		"Apple auto demo reaches generic generation."
	)
	scene.call("debug_set_auto_demo_time", 1.0)
	var motion_stats: Dictionary = polygon_asset.call("get_runtime_stats")
	var downward_position := (polygon_asset as Node2D).position
	_check(
		_array_to_vector2(
			motion_stats.get("movement_target_direction", [])
		).y > 0.8
		and float(motion_stats.get("movement_amount", 0.0)) > 0.0
		and is_zero_approx(
			float(motion_stats.get("dissolve_progress", -1.0))
		),
		"Apple auto demo reaches spring-driven downward deformation."
	)
	scene.call("debug_set_auto_demo_time", 2.0)
	var leftward_stats: Dictionary = polygon_asset.call(
		"get_runtime_stats"
	)
	var leftward_position := (polygon_asset as Node2D).position
	_check(
		_array_to_vector2(
			leftward_stats.get("movement_target_direction", [])
		).x < -0.95
		and not leftward_position.is_equal_approx(downward_position),
		"Apple auto demo moves continuously and turns the spring target."
	)
	scene.call("debug_set_auto_demo_time", 6.2)
	var dissolve_stats: Dictionary = polygon_asset.call(
		"get_runtime_stats"
	)
	_check(
		float(dissolve_stats.get("dissolve_progress", 0.0)) > 0.4,
		"Apple auto demo reaches generic dissolve."
	)
	scene.queue_free()
	await process_frame


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false}
	if not parser.data is Dictionary:
		return {"ok": false}
	return {"ok": true, "data": parser.data}


func _vector2_array_from_json(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for point_value: Variant in value:
		if (
			point_value is Array
			and (point_value as Array).size() == 2
		):
			var point: Array = point_value
			result.append(Vector2(float(point[0]), float(point[1])))
	return result


func _array_to_vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	var values: Array = value
	return Vector2(float(values[0]), float(values[1]))


func _variants_equivalent(first: Variant, second: Variant) -> bool:
	if first is Dictionary and second is Dictionary:
		var first_dictionary: Dictionary = first
		var second_dictionary: Dictionary = second
		if first_dictionary.size() != second_dictionary.size():
			return false
		for key: Variant in first_dictionary:
			if (
				not second_dictionary.has(key)
				or not _variants_equivalent(
					first_dictionary[key],
					second_dictionary[key]
				)
			):
				return false
		return true
	if first is Array and second is Array:
		var first_array: Array = first
		var second_array: Array = second
		if first_array.size() != second_array.size():
			return false
		for index in range(first_array.size()):
			if not _variants_equivalent(
				first_array[index],
				second_array[index]
			):
				return false
		return true
	if (
		(first is int or first is float)
		and (second is int or second is float)
	):
		return is_equal_approx(float(first), float(second))
	return first == second


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures > 0:
		push_error(
			"POLYGON_APPLE_ASSET_SMOKE_FAILED: %d failure(s)"
			% _failures
		)
		quit(1)
		return
	print("POLYGON_APPLE_ASSET_SMOKE_OK")
	quit(0)
