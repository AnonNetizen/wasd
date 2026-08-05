shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 dark_color : source_color = vec4(0.012, 0.002, 0.008, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luma = max(source.r, max(source.g, source.b));
	float alpha = smoothstep(0.02, 0.72, luma) * opacity;
	COLOR = vec4(dark_color.rgb, alpha);
}
