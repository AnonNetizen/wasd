shader_type canvas_item;
render_mode unshaded;

uniform float animation_time = 0.0;
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

void fragment() {
	vec4 face_color = vec4(COLOR.rgb, 1.0);
	float interior_factor = outline_mode ? 0.0 : 1.0;

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
