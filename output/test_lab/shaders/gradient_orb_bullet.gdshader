shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 body_color : source_color = vec4(0.902, 0.161, 0.208, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.949, 0.929, 1.0);
uniform vec2 highlight_center = vec2(0.34, 0.32);
uniform float highlight_radius : hint_range(0.1, 1.0, 0.01) = 0.72;
uniform float highlight_curve : hint_range(0.25, 4.0, 0.05) = 1.35;
uniform float circle_radius : hint_range(0.45, 0.5, 0.001) = 0.49;

varying vec2 orb_local_position;

void vertex() {
	orb_local_position = VERTEX;
}

void fragment() {
	vec2 gradient_uv = orb_local_position * 0.5 + vec2(0.5);
	vec2 centered_uv = gradient_uv - vec2(0.5);
	float center_distance = length(centered_uv);
	float edge_width = clamp(fwidth(center_distance) * 1.25, 0.001, 0.03);
	float circle_alpha = 1.0 - smoothstep(
		circle_radius - edge_width,
		circle_radius,
		center_distance
	);

	float highlight_distance = distance(gradient_uv, highlight_center);
	float highlight_mix = 1.0 - smoothstep(0.0, highlight_radius, highlight_distance);
	highlight_mix = pow(clamp(highlight_mix, 0.0, 1.0), highlight_curve);
	float rim_fade = 1.0 - smoothstep(
		circle_radius * 0.76,
		circle_radius,
		center_distance
	);
	highlight_mix *= rim_fade;

	vec3 result_color = mix(body_color.rgb, highlight_color.rgb, highlight_mix);
	COLOR = vec4(result_color, body_color.a * circle_alpha);
}
