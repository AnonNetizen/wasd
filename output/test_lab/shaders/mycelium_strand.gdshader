shader_type canvas_item;
render_mode blend_mix;

uniform float time = 0.0;
uniform float growth_amount = 1.0;
uniform float decay_amount = 0.0;
uniform float activation = 0.0;
uniform float line_phase = 0.0;
uniform float flow_speed = 0.16;
uniform float growth_start = 0.0;
uniform float growth_end = 1.0;
uniform float strand_width = 2.0;
uniform vec4 dormant_color : source_color = vec4(0.265, 0.115, 0.200, 0.58);
uniform vec4 active_color : source_color = vec4(0.680, 0.245, 0.410, 0.66);
uniform vec4 pulse_color : source_color = vec4(0.760, 0.560, 0.860, 0.40);

void fragment() {
	float reveal = smoothstep(growth_start, growth_end, growth_amount);
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float taper = 1.0 - smoothstep(0.70, 1.0, along);
	float core = 1.0 - smoothstep(0.18, 0.92, across);
	float feather = (1.0 - smoothstep(0.58, 1.0, across)) * 0.32;
	float crawl = fract(along * 1.45 - time * flow_speed + line_phase);
	float pulse = smoothstep(0.88, 1.0, crawl) * smoothstep(0.0, 0.15, crawl);
	float breathing = 0.82 + sin(time * 1.35 + line_phase + along * 3.5) * 0.10;

	vec4 strand_color = mix(dormant_color, active_color, activation);
	vec3 color = strand_color.rgb + pulse_color.rgb * pulse * (0.12 + activation * 0.48);
	color = mix(color, dormant_color.rgb * 0.68, decay_amount * 0.36);

	float alpha = (core + feather) * strand_color.a * taper * breathing;
	alpha += pulse * pulse_color.a * activation * 0.32;
	alpha *= 0.54 + min(strand_width, 3.0) * 0.10;
	alpha *= max(0.16, reveal);
	alpha *= 1.0 - decay_amount * 0.62;

	COLOR = vec4(color, alpha) * COLOR;
}
