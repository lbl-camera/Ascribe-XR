// Benchmark variant where STEP_SIZE and MAX_STEPS are uniforms so the
// volume_benchmark script can sweep them at runtime. HARD_MAX_STEPS is the
// compile-time loop bound; max_steps is the runtime-controlled exit.
//
// Used by testscenes/volume_benchmark_step_size.tscn.

shader_type spatial;
render_mode unshaded, cull_front;

const int MAX_EXCLUSION_PLANES = 4;
const int HARD_MAX_STEPS = 4096;

uniform sampler3D texture_volume : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D gradient : filter_linear_mipmap, repeat_disable;
uniform float zoom = 2;
uniform int layers = 2;
uniform float opacity = 1;
uniform float gamma = 1;
uniform float color_scalar = 1;
uniform int max_steps = 640;
uniform float step_size = 0.002;
uniform int num_exclusion_planes = 0;
uniform vec4[MAX_EXCLUSION_PLANES] exclusion_planes;

varying vec3 pos_local;
varying vec3 pos_world;
varying mat3 inv_model_rotation;
varying vec3 inv_model_translation;
varying vec3 world_camera;
varying vec3 world_position;

void vertex() {
    world_position = VERTEX;
    world_camera = (inverse(MODELVIEW_MATRIX) * vec4(0, 0, 0, 1)).xyz;
    world_camera += EYE_OFFSET;
}

bool is_outside_exclusion_planes(vec3 point) {
    for (int i = 0; i < num_exclusion_planes; ++i) {
        vec4 plane = exclusion_planes[i];
        if (dot(point, plane.xyz) > plane.w) {
            return true;
        }
    }
    return false;
}

vec4 raymarch(vec3 ray_origin, vec3 ray_dir) {
    vec4 accumulated_color = vec4(0.0, 0.0, 0.0, 0.0);
    float total_opacity = 0.0;

    for (int i = 0; i < HARD_MAX_STEPS; ++i) {
        if (i >= max_steps)
            break;
        ray_origin += ray_dir * step_size;

        vec3 tex_sample_pt = ((ray_origin * zoom) / 2.0) + vec3(0.5, 0.5, 0.5);

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
    vec3 ro = world_camera;
    vec3 rd = normalize(world_position - ro);

    vec3 half_extents = vec3(0.5, 0.5, 0.5);

    vec3 t_min = (-half_extents - ro) / rd;
    vec3 t_max = (half_extents - ro) / rd;

    vec3 t_near = min(t_min, t_max);
    vec3 t_far = max(t_min, t_max);

    float t_entry = max(max(t_near.x, t_near.y), t_near.z);
    ro += rd * t_entry;

    vec4 col = raymarch(ro, rd);

    col *= color_scalar;

    ALBEDO = col.rgb;
    ALPHA = col.a;

    if (VIEW_INDEX == VIEW_RIGHT)
        ALBEDO.g = 1.0;
}
