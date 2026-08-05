shader_type canvas_item;

uniform vec4 main_primary : source_color = vec4(0.408, 0.737, 0.867, 1.0);
uniform vec4 sub_primary : source_color = vec4(0.929, 0.184, 0.447, 1.0);
uniform vec4 presentation_tint : source_color = vec4(1.0);
uniform float presentation_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float animation_time = 0.0;
uniform float body_radius = 25.0;

varying vec2 local_position;


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


float fbm(vec2 point) {
	float total = 0.0;
	float amplitude = 0.55;
	mat2 turn = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int octave = 0; octave < 4; octave++) {
		total += value_noise(point) * amplitude;
		point = turn * point * 1.92 + vec2(3.17, -1.83);
		amplitude *= 0.48;
	}
	return total;
}


void vertex() {
	local_position = VERTEX;
}


void fragment() {
	vec2 point = local_position / max(body_radius, 0.001);
	float radius = length(point);
	float angle = atan(point.y, point.x);
	float time = animation_time;

	vec2 clockwise_domain = vec2(
		cos(angle - time * 0.52),
		sin(angle - time * 0.52)
	) * (2.0 + radius * 2.9);
	vec2 counter_domain = vec2(
		cos(angle + time * 0.47),
		sin(angle + time * 0.47)
	) * (2.1 + radius * 3.1);
	clockwise_domain += point * 2.6 + vec2(time * 0.13, -time * 0.09);
	counter_domain += point.yx * vec2(-2.4, 2.7) + vec2(-time * 0.11, time * 0.08);

	float clockwise_gas = fbm(clockwise_domain);
	float counter_gas = fbm(counter_domain + vec2(7.3, -4.1));
	float dividing_flow = sin(
		angle + radius * 2.35 - time * 0.34
		+ (clockwise_gas - counter_gas) * 2.15
	);
	float sub_mix = smoothstep(-0.11, 0.11, dividing_flow);

	float main_density = 0.75 + clockwise_gas * 0.31;
	float sub_density = 0.75 + counter_gas * 0.31;
	vec3 main_gas = main_primary.rgb * main_density;
	vec3 sub_gas = sub_primary.rgb * sub_density;
	vec3 color = mix(main_gas, sub_gas, sub_mix);

	float interface_mist = 1.0 - smoothstep(0.0, 0.22, abs(dividing_flow));
	color = mix(color, mix(main_primary.rgb, sub_primary.rgb, 0.5), interface_mist * 0.18);
	float inner_rim = smoothstep(0.72, 0.98, radius);
	color = mix(color, main_primary.rgb, inner_rim * 0.42);
	float wet_light = smoothstep(0.62, 0.94, dot(normalize(point + vec2(0.0001)), normalize(vec2(-0.72, -0.69))));
	color += mix(main_primary.rgb, sub_primary.rgb, 0.5) * wet_light * (1.0 - radius) * 0.13;

	color *= presentation_tint.rgb;
	COLOR = vec4(color, presentation_alpha * presentation_tint.a);
}
