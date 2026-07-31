shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.025, 0.075, 0.068, 1.0);
uniform float outline_width = 0.045;


void vertex() {
	VERTEX += NORMAL * outline_width;
}


void fragment() {
	ALBEDO = outline_color.rgb;
}
