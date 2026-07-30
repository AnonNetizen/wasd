shader_type canvas_item;
render_mode unshaded;

uniform vec2 asset_half_size = vec2(128.0, 96.0);
uniform float animation_time = 0.0;
uniform float page_turn_progress : hint_range(0.0, 1.0) = 0.0;
uniform float clear_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_mode = false;

void vertex() {
	float half_width = max(asset_half_size.x, 1.0);
	float half_height = max(asset_half_size.y, 1.0);
	float outer_weight = clamp(abs(VERTEX.x) / half_width, 0.0, 1.0);
	float spine_guard = smoothstep(0.04, 0.22, outer_weight);
	float idle_wave = sin(
		animation_time * 1.35
		+ VERTEX.y * 0.028
		+ sign(VERTEX.x) * 0.75
	);
	VERTEX.y += idle_wave * 2.4 * outer_weight * outer_weight * spine_guard;

	float right_page = step(0.001, VERTEX.x);
	float fold = sin(page_turn_progress * 3.14159265);
	float vertical_center_weight = 1.0 - clamp(abs(VERTEX.y) / half_height, 0.0, 1.0);
	VERTEX.x -= right_page * fold * (VERTEX.x * 0.98 + 7.0 * outer_weight);
	VERTEX.y -= right_page * fold * 11.0 * outer_weight * vertical_center_weight;
}

void fragment() {
	vec4 face_color = COLOR;
	float visibility = 1.0;
	if (outline_mode) {
		visibility = 1.0 - smoothstep(0.94, 1.0, clear_progress);
	} else if (clear_progress > 0.0001) {
		visibility = smoothstep(clear_progress, clear_progress + 0.028, UV.x);
	}
	COLOR = vec4(face_color.rgb, face_color.a * visibility);
}
