shader_type canvas_item;
render_mode unshaded;

uniform vec2 asset_half_size = vec2(128.0, 96.0);
uniform float animation_time = 0.0;
uniform float page_turn_progress : hint_range(0.0, 1.0) = 0.0;
uniform float clear_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_mode = false;
uniform vec4 page_fold_light : source_color = vec4(0.95, 0.80, 0.52, 1.0);
uniform vec4 page_fold_shadow : source_color = vec4(0.55, 0.44, 0.36, 1.0);

void vertex() {
	float half_width = max(asset_half_size.x, 1.0);
	float half_height = max(asset_half_size.y, 1.0);
	float vertical_weight = clamp(abs(VERTEX.y) / half_height, 0.0, 1.0);
	float turnable_page = outline_mode ? 0.0 : step(0.75, UV.y);

	float right_page_position = clamp(VERTEX.x / half_width, 0.0, 1.0);
	float turn_envelope = sin(page_turn_progress * 3.14159265);
	float crease_center = mix(0.18, 0.82, page_turn_progress);
	float crease_offset = right_page_position - crease_center;
	float crease_band = exp(-crease_offset * crease_offset * 34.0);
	float turn_boundary_guard = (
		smoothstep(0.04, 0.20, right_page_position)
		* (1.0 - smoothstep(0.76, 0.98, right_page_position))
		* (1.0 - smoothstep(0.72, 0.97, vertical_weight))
	);
	float crease = turnable_page * turn_envelope * crease_band * turn_boundary_guard;
	VERTEX.x -= crease * (10.0 + 7.0 * (1.0 - right_page_position));
	VERTEX.y += crease * 9.0 * sin(VERTEX.y / half_height * 1.57079633);
}

void fragment() {
	vec4 face_color = COLOR;
	float turnable_page = outline_mode ? 0.0 : step(0.75, UV.y);
	float turn_envelope = sin(page_turn_progress * 3.14159265);
	float block_phase = fract(UV.x * 17.0);
	float color_wave = 0.5 + 0.5 * sin(
		page_turn_progress * 6.28318531
		+ block_phase * 6.28318531
	);
	vec3 fold_color = mix(page_fold_shadow.rgb, page_fold_light.rgb, color_wave);
	face_color.rgb = mix(
		face_color.rgb,
		fold_color,
		turnable_page * turn_envelope * (0.18 + color_wave * 0.30)
	);
	float visibility = 1.0;
	if (outline_mode) {
		visibility = 1.0 - smoothstep(0.94, 1.0, clear_progress);
	} else if (clear_progress > 0.0001) {
		visibility = smoothstep(clear_progress, clear_progress + 0.028, UV.x);
	}
	COLOR = vec4(face_color.rgb, face_color.a * visibility);
}
