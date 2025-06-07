shader_type spatial;
render_mode unshaded, cull_front;

const int MAX_EXCLUSION_PLANES = 4;

uniform sampler3D texture_volume : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D gradient : filter_linear_mipmap, repeat_disable;
uniform float zoom = 2;
uniform int layers = 2;
uniform float opacity = 1;
uniform float gamma = 1;
uniform float color_scalar = 1;
uniform int num_exclusion_planes = 0;
uniform vec4[MAX_EXCLUSION_PLANES] exclusion_planes;

varying vec3 pos_local;
varying vec3 pos_world;
varying mat3 inv_model_rotation; // Precomputed rotation matrix
varying vec3 inv_model_translation; // Precomputed translation vector

void vertex() {
    pos_local = VERTEX;
    pos_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    mat4 inv_model_mtx = inverse(MODEL_MATRIX);
    inv_model_rotation = mat3(inv_model_mtx); // Extract rotation matrix
    inv_model_translation = inv_model_mtx[3].xyz; // Extract translation
}

vec3 isect_plane(vec3 view_origin, vec3 view_dir, vec3 plane_point, vec3 plane_dir) {
    float s = dot((plane_point - view_origin), plane_dir) / dot(view_dir, plane_dir);
    return s * view_dir + view_origin;
}

void fragment() {
    vec3 model_origin_world = MODEL_MATRIX[3].xyz;
    vec3 plane_norm = normalize(CAMERA_POSITION_WORLD - model_origin_world);

    vec4 col = vec4(0, 0, 0, 0);

    for (int layer_idx = 0; layer_idx < layers; ++layer_idx) {
        float layer_frac = float(layer_idx + 1) / float(layers + 1);
        vec3 plane_origin = model_origin_world + plane_norm * (layer_frac - 0.5) * 2.0;
        vec3 p_world = isect_plane(CAMERA_POSITION_WORLD, pos_world - CAMERA_POSITION_WORLD, plane_origin, plane_norm);

        // Exclusion plane check (vectorized approach)
        float exclusion_test = 0.0;
        for (int i = 0; i < min(num_exclusion_planes, MAX_EXCLUSION_PLANES); ++i) {
            exclusion_test += step(0.0, dot(vec4(p_world, -1.0), exclusion_planes[i]));
        }
        if (exclusion_test > 0.0) continue; // If any plane rejects, skip this layer

        // Transform point to local space using precomputed inverse
        vec3 p_local = inv_model_rotation * p_world + inv_model_translation;

        // Compute texture sample position (without clamping)
        vec3 tex_sample_pt = ((p_local * zoom) / 2.0) + vec3(0.5, 0.5, 0.5);

        // Skip invalid samples
        if (any(lessThan(tex_sample_pt, vec3(0.0))) || any(greaterThan(tex_sample_pt, vec3(1.0))))
            continue;

        vec4 layer_col = texture(texture_volume, tex_sample_pt);
        layer_col = texture(gradient, vec2(pow(layer_col.r, gamma), 0));
        layer_col.a *= opacity;
        layer_col *= color_scalar;

        col = mix(col, layer_col, layer_col.a);
    }

    ALBEDO = col.rgb;
    ALPHA = col.a;
}