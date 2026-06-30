shader_type canvas_item;
render_mode blend_mix;

uniform float time = 0.0;
uniform float growth_amount = 1.0;
uniform float decay_amount = 0.0;
uniform vec2 focus_position = vec2(0.5, 0.5);
uniform float focus_radius = 0.18;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	vec2 warped_uv = centered_uv + vec2(
		value_noise(UV * 3.4 + vec2(time * 0.018, 0.0)) - 0.5,
		value_noise(UV * 3.2 + vec2(0.0, time * 0.014)) - 0.5
	) * 0.11;

	float distance_from_center = length(warped_uv * vec2(1.0, 0.82));
	float low_noise = value_noise(UV * 4.2 + time * 0.018);
	float fine_noise = value_noise(UV * 18.0 - time * 0.025);
	float stain_shape = smoothstep(1.02, 0.58, distance_from_center + (low_noise - 0.5) * 0.22);
	float edge_bleed = smoothstep(0.98, 0.72, distance_from_center + (low_noise - 0.5) * 0.16);
	float wet_sheen = smoothstep(0.52, 1.0, fine_noise) * stain_shape;
	float focus_glow = 1.0 - smoothstep(0.0, focus_radius, distance(UV, focus_position));

	vec3 dry_color = vec3(0.045, 0.033, 0.041);
	vec3 wet_color = vec3(0.115, 0.060, 0.088);
	vec3 edge_color = vec3(0.280, 0.165, 0.145);
	vec3 glow_color = vec3(0.420, 0.350, 0.210);
	vec3 color = mix(dry_color, wet_color, stain_shape);
	color = mix(color, edge_color, edge_bleed * 0.28);
	color += glow_color * wet_sheen * 0.055 * (0.45 + growth_amount * 0.55);
	color += vec3(0.18, 0.25, 0.22) * focus_glow * 0.055 * growth_amount;
	color = mix(color, dry_color * 0.82, decay_amount * 0.22);

	float alpha = stain_shape * (0.34 + growth_amount * 0.30) + wet_sheen * 0.12;
	alpha *= 1.0 - decay_amount * 0.36;
	COLOR = vec4(color, alpha);
}
