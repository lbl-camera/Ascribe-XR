shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.1, 1.0);
uniform float edge_width = 0.04;
uniform float glow_strength = 2.0;

void fragment() {
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge = 1.0 - smoothstep(0.0, edge_width, d);

	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * edge * glow_strength;
	ALPHA = edge * glow_color.a;
}