shader_type spatial;
render_mode unshaded, cull_front;

const int MAX_EXCLUSION_PLANES = 4;
const int MAX_STEPS = 128;
const float STEP_SIZE = 0.01;

uniform sampler3D texture_volume : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D gradient : filter_linear_mipmap, repeat_disable;
uniform float zoom = 2.0;
uniform float opacity = 1.0;
uniform float gamma = 1.0;
uniform float color_scalar = 1.0;
uniform int num_exclusion_planes = 0;
uniform vec4[MAX_EXCLUSION_PLANES] exclusion_planes;

varying vec3 pos_local;
varying vec3 pos_world;
varying vec3 eye_pos_world;
varying vec3 frag_world_pos;


// Function to check if a point is outside of an exclusion plane
bool is_outside_exclusion_planes(vec3 point) {
    for (int i = 0; i < num_exclusion_planes; ++i) {
        vec4 plane = exclusion_planes[i];
        if (dot(point, plane.xyz) > plane.w) {
            return true;
        }
    }
    return false;
}


void vertex() {
    pos_local = VERTEX;
    pos_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Compute per-eye world-space camera position
    eye_pos_world = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
}

// Raymarching function
vec4 raymarch(vec3 ray_origin, vec3 ray_dir) {
    vec4 accumulated_color = vec4(0.0);
    float total_opacity = 0.0;

    for (int i = 0; i < MAX_STEPS; ++i) {
        ray_origin += ray_dir * STEP_SIZE;

        vec3 tex_sample_pt = ((ray_origin * zoom) / 2.0) + vec3(0.5);
        if (any(lessThan(tex_sample_pt, vec3(0.0))) || any(greaterThan(tex_sample_pt, vec3(1.0))))
            break;

        if (is_outside_exclusion_planes(ray_origin)) {
            continue;
        }

        vec4 sample = texture(texture_volume, tex_sample_pt);
        sample = texture(gradient, vec2(pow(sample.r, gamma), 0));

        float sample_opacity = sample.a * opacity;
        accumulated_color.rgb += sample.rgb * sample_opacity * (1.0 - total_opacity);
        total_opacity += sample_opacity;

        if (total_opacity >= 1.0)
            break;
    }

    accumulated_color.a = total_opacity;
    return accumulated_color;
}



void fragment() {
    vec3 ro_world = eye_pos_world;
    vec3 rd_world = normalize(pos_world - ro_world);

    vec3 ro = (inverse(MODEL_MATRIX) * vec4(ro_world, 1.0)).xyz;
    vec3 rd = normalize((inverse(MODEL_MATRIX) * vec4(rd_world, 0.0)).xyz);

    // Ray-box entry logic
    vec3 half_extents = vec3(0.5);
    vec3 t_min = (-half_extents - ro) / rd;
    vec3 t_max = ( half_extents - ro) / rd;
    vec3 t_near = min(t_min, t_max);
    float t_entry = max(max(t_near.x, t_near.y), t_near.z);
    ro += rd * max(t_entry, 0.0);

    vec4 col = raymarch(ro, rd);
    col *= color_scalar;

    ALBEDO = col.rgb;
    ALPHA = col.a;
}