shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 highlight_color : source_color = vec4(0.68, 1.0, 0.86, 1.0);
uniform float coat_offset = 0.012;
uniform float pulse = 0.0;

varying vec3 local_vertex;


void vertex() {
	local_vertex = VERTEX;
	VERTEX += NORMAL * coat_offset;
}


void fragment() {
	vec2 face_point = vec2(local_vertex.x / 1.32, (local_vertex.y - 2.05) / 2.25);
	float front_face = smoothstep(0.48, 0.90, NORMAL.z);
	float streak = 1.0 - smoothstep(
		0.62,
		1.02,
		length((face_point - vec2(-0.31, 0.35)) / vec2(0.22, 0.72))
	);
	float edge_light = pow(
		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		3.0
	);
	float intensity = streak * front_face * (0.12 + pulse * 0.05);
	intensity += edge_light * (0.035 + pulse * 0.025);
	ALBEDO = highlight_color.rgb;
	ALPHA = clamp(intensity, 0.0, 0.24);
}
