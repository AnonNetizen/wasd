shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.22, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float pulse = 0.88 + 0.12 * sin(TIME * 8.0);
	vec3 glow = glow_color.rgb * source.a * intensity * pulse;
	COLOR = vec4(max(source.rgb, glow), source.a * glow_color.a);
}
