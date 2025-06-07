shader_type spatial;
render_mode unshaded, cull_front;

uniform sampler3D texture_volume : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D gradient : filter_linear_mipmap, repeat_disable;
uniform float zoom = 2.0;
uniform float opacity = 1.0;
uniform float gamma = 1.0;
uniform float color_scalar = 1.0;
uniform int max_steps = 64;  // Max number of raymarch steps
uniform float step_size = 0.02;  // Step size for raymarching

varying vec3 pos_local;
varying vec3 pos_world;

void vertex() {
    pos_local = VERTEX;
    pos_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 ray_origin = CAMERA_POSITION_WORLD;
    vec3 ray_dir = normalize(pos_world - ray_origin);

    vec3 p_local = (inverse(MODEL_MATRIX) * vec4(ray_origin, 1.0)).xyz;
    vec3 ray_local = normalize((inverse(MODEL_MATRIX) * vec4(ray_dir, 0.0)).xyz);

    vec4 col = vec4(0.0);
    float alpha_accum = 0.0;

    for (int i = 0; i < max_steps; i++) {
        p_local += ray_local * step_size;

        vec3 tex_coord = ((p_local * zoom) / 2.0) + vec3(0.5);
        if (any(lessThan(tex_coord, vec3(0.0))) || any(greaterThan(tex_coord, vec3(1.0))))
            break;

        vec4 sample_col = texture(texture_volume, tex_coord);
        sample_col = texture(gradient, vec2(pow(sample_col.r, gamma), 0));
        sample_col.a *= opacity;
        sample_col *= color_scalar;

        col = mix(col, sample_col, sample_col.a);
        alpha_accum += sample_col.a;
        if (alpha_accum >= 1.0) break;
    }

    ALBEDO = col.rgb;
    ALPHA = col.a;
}