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
uniform float gap_phase = 0.0;
uniform float strand_width = 1.0;
uniform vec2 focus_position = vec2(0.5, 0.5);
uniform float focus_radius = 0.18;
uniform vec4 dormant_color : source_color = vec4(0.72, 0.66, 0.52, 0.74);
uniform vec4 active_color : source_color = vec4(0.92, 0.68, 0.36, 0.62);
uniform vec4 pulse_color : source_color = vec4(0.36, 0.62, 0.68, 0.46);

void fragment() {
	float reveal = smoothstep(growth_start, growth_end, growth_amount);
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float core = max(0.55, 1.0 - smoothstep(0.18, 0.96, across));
	float feather = max(0.18, (1.0 - smoothstep(0.50, 1.0, across)) * 0.32);
	float crawl = fract(along * 1.8 - time * flow_speed + line_phase + gap_phase);
	float pulse = smoothstep(0.90, 1.0, crawl) * smoothstep(0.0, 0.12, crawl);
	float breathing = 0.78 + sin(time * 1.7 + line_phase + along * 5.0) * 0.14;
	float broken = mix(0.62, 1.0, smoothstep(0.18, 0.56, fract(along * 7.0 + gap_phase)));

	vec4 strand_color = mix(dormant_color, active_color, activation);
	vec3 color = strand_color.rgb;
	color += pulse_color.rgb * pulse * (0.18 + activation * 0.68);
	color = mix(color, dormant_color.rgb * 0.72, decay_amount * 0.42);

	float alpha = (core + feather) * strand_color.a * breathing * broken;
	alpha += pulse * pulse_color.a * activation * 0.55;
	alpha *= 0.62 + min(strand_width, 2.0) * 0.16;
	alpha *= max(0.18, reveal);
	alpha *= 1.0 - decay_amount * 0.58;

	COLOR = vec4(color, alpha) * COLOR;
}
