shader_type canvas_item;
render_mode unshaded;

uniform vec2 asset_half_size = vec2(128.0, 96.0);
uniform float animation_time = 0.0;
uniform float motion_progress : hint_range(0.0, 1.0) = 0.0;
uniform float motion_strength : hint_range(0.0, 1.0) = 0.0;
uniform float generation_progress : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_mode = false;
uniform vec2 motion_axis = vec2(1.0, 0.0);
uniform float motion_origin = 0.0;
uniform float motion_span = 1.0;
uniform float motion_tangent_center = 0.0;
uniform float motion_tangent_span = 1.0;
uniform vec4 generation_tint : source_color = vec4(0.79, 0.60, 0.36, 1.0);
uniform vec4 dissolve_tint : source_color = vec4(0.31, 0.24, 0.43, 1.0);

uniform float page_turn_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 page_fold_light : source_color = vec4(0.95, 0.80, 0.52, 1.0);
uniform vec4 page_fold_shadow : source_color = vec4(0.55, 0.44, 0.36, 1.0);

void vertex() {
	vec2 axis = normalize(motion_axis);
	vec2 tangent = vec2(-axis.y, axis.x);
	float primary_position = clamp(
		(dot(VERTEX, axis) - motion_origin) / max(motion_span, 1.0),
		0.0,
		1.0
	);
	float tangent_position = clamp(
		(dot(VERTEX, tangent) - motion_tangent_center)
		/ max(motion_tangent_span * 0.5, 1.0),
		-1.0,
		1.0
	);
	float vertex_motion_weight = outline_mode ? 0.0 : UV.y;
	float motion_guard = (
		smoothstep(0.02, 0.16, primary_position)
		* (1.0 - smoothstep(0.84, 0.98, primary_position))
		* (1.0 - smoothstep(0.82, 1.0, abs(tangent_position)))
	);
	float motion_phase = (
		animation_time * 1.35
		+ motion_progress * 6.28318531
		+ primary_position * 3.4
		+ tangent_position * 1.8
	);
	float sway = (
		sin(motion_phase)
		* motion_strength
		* vertex_motion_weight
		* motion_guard
	);
	VERTEX += tangent * sway * 4.0;
	VERTEX += axis * cos(motion_phase * 0.73) * sway * 1.4;

	float page_weight = step(0.75, vertex_motion_weight);
	float page_turn_envelope = sin(page_turn_progress * 3.14159265);
	float crease_center = mix(0.18, 0.82, page_turn_progress);
	float crease_offset = primary_position - crease_center;
	float crease_band = exp(-crease_offset * crease_offset * 34.0);
	float crease_guard = (
		smoothstep(0.04, 0.20, primary_position)
		* (1.0 - smoothstep(0.76, 0.98, primary_position))
		* (1.0 - smoothstep(0.72, 0.97, abs(tangent_position)))
	);
	float crease = (
		page_weight
		* page_turn_envelope
		* crease_band
		* crease_guard
	);
	VERTEX -= axis * crease * (10.0 + 7.0 * (1.0 - primary_position));
	VERTEX += tangent * crease * 9.0 * sin(tangent_position * 1.57079633);
}

void fragment() {
	vec4 face_color = vec4(COLOR.rgb, 1.0);
	float primary_face = outline_mode ? 0.0 : step(0.75, COLOR.a);
	float interior_factor = outline_mode ? 0.0 : 1.0;
	float motion_wave = 0.5 + 0.5 * sin(
		animation_time * 1.7
		+ motion_progress * 6.28318531
		+ UV.x * 12.0
	);
	face_color.rgb *= 1.0 + (
		primary_face
		* motion_strength
		* (motion_wave - 0.5)
		* 0.10
	);

	float page_turn_envelope = sin(page_turn_progress * 3.14159265);
	float block_phase = fract(UV.x * 17.0);
	float page_color_wave = 0.5 + 0.5 * sin(
		page_turn_progress * 6.28318531
		+ block_phase * 6.28318531
	);
	vec3 page_fold_color = mix(
		page_fold_shadow.rgb,
		page_fold_light.rgb,
		page_color_wave
	);
	face_color.rgb = mix(
		face_color.rgb,
		page_fold_color,
		primary_face
		* page_turn_envelope
		* (0.18 + page_color_wave * 0.30)
	);

	float generation_visibility = smoothstep(
		0.0,
		0.08,
		generation_progress
	);
	float dissolve_visibility = 1.0 - smoothstep(
		0.94,
		1.0,
		dissolve_progress
	);
	if (!outline_mode) {
		if (generation_progress <= 0.0001) {
			generation_visibility = 0.0;
		} else if (generation_progress >= 0.9999) {
			generation_visibility = 1.0;
		} else {
			generation_visibility = 1.0 - smoothstep(
				generation_progress,
				generation_progress + 0.028,
				UV.x
			);
		}
		if (dissolve_progress <= 0.0001) {
			dissolve_visibility = 1.0;
		} else if (dissolve_progress >= 0.9999) {
			dissolve_visibility = 0.0;
		} else {
			dissolve_visibility = smoothstep(
				dissolve_progress,
				dissolve_progress + 0.028,
				UV.x
			);
		}
	}
	float generation_edge = 1.0 - smoothstep(
		0.02,
		0.10,
		abs(UV.x - generation_progress)
	);
	float dissolve_edge = 1.0 - smoothstep(
		0.02,
		0.10,
		abs(UV.x - dissolve_progress)
	);
	face_color.rgb = mix(
		face_color.rgb,
		generation_tint.rgb,
		generation_edge * interior_factor * 0.28
	);
	face_color.rgb = mix(
		face_color.rgb,
		dissolve_tint.rgb,
		dissolve_edge * interior_factor * 0.34
	);
	COLOR = vec4(
		face_color.rgb,
		face_color.a * generation_visibility * dissolve_visibility
	);
}
