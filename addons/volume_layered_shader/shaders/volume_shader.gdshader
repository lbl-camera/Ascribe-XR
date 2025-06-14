shader_type spatial;
render_mode unshaded, cull_front;

const int MAX_EXCLUSION_PLANES = 4;
const int MAX_STEPS = 128*2;
const float STEP_SIZE = 0.01/2.;

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
varying vec3 world_camera;
varying vec3 world_position;

void vertex() {
	world_position = VERTEX;
	world_camera = (inverse(MODELVIEW_MATRIX) * vec4(0, 0, 0, 1)).xyz; //object space
	//world_camera = ( CAMERA_MATRIX  * vec4(0, 0, 0, 1)).xyz; //uncomment this to raymarch in world space
	world_camera += EYE_OFFSET;
}

// Function to check if a point is outside of an exclusion plane
bool is_outside_exclusion_planes(vec3 point) {
    for (int i = 0; i < num_exclusion_planes; ++i) {
        // Exclusion planes are stored in vec4 (x, y, z) as the normal and w as the distance
        vec4 plane = exclusion_planes[i];
        // Dot product between point and plane normal and check if it's greater than the plane's distance
        if (dot(point, plane.xyz) > plane.w) {
            return true; // Point is outside this exclusion plane
        }
    }
    return false;
}

// Raymarching function
vec4 raymarch(vec3 ray_origin, vec3 ray_dir) {
    vec4 accumulated_color = vec4(0.0, 0.0, 0.0, 0.0);
    float total_opacity = 0.0;

    for (int i = 0; i < MAX_STEPS; ++i) {
        // Step along the ray
        ray_origin += ray_dir * STEP_SIZE;

        // Sample the texture volume
        vec3 tex_sample_pt = ((ray_origin * zoom) / 2.0) + vec3(0.5, 0.5, 0.5);

        // Skip invalid samples
        if (any(lessThan(tex_sample_pt, vec3(0.0))) || any(greaterThan(tex_sample_pt, vec3(1.0))))
            break;

        // Check if the current point is outside of any exclusion planes
        if (is_outside_exclusion_planes(ray_origin)) {
            continue; // Skip this sample if it's outside of an exclusion plane
        }

        vec4 sample = texture(texture_volume, tex_sample_pt);
        sample = texture(gradient, vec2(pow(sample.r, gamma), 0));

        // Accumulate color and opacity
        float sample_opacity = sample.a * opacity;
        accumulated_color.rgb += sample.rgb * sample_opacity * (1.0 - total_opacity);
        total_opacity += sample_opacity;

        // If the opacity reaches 1, we can break out early
        if (total_opacity >= 1.0)
            break;
    }

    accumulated_color.a = total_opacity;
    return accumulated_color;
}

void fragment() {
    vec3 ro = world_camera;
    vec3 rd = normalize(world_position - ro);

    // Assuming your cube is centered at (0, 0, 0) and has size 1 (you can adjust this to your volume's size).
    vec3 half_extents = vec3(0.5, 0.5, 0.5); // Adjust this to match the cube's half-extents

    // Ray-box intersection logic to clamp ray origin to the surface of the cube
    vec3 t_min = ( -half_extents - ro ) / rd; // Compute entry point of the ray
    vec3 t_max = ( half_extents - ro ) / rd;  // Compute exit point of the ray

    // Ensure t_min is less than t_max
    vec3 t_near = min(t_min, t_max);
    vec3 t_far = max(t_min, t_max);

    // Find the largest of the entry points to determine where the ray first enters the box
    float t_entry = max(max(t_near.x, t_near.y), t_near.z);
    // The ray origin should be adjusted to this entry point
    ro += rd * t_entry;

    // Now perform raymarching from the adjusted origin
    vec4 col = raymarch(ro, rd);

    // Apply color scalar
    col *= color_scalar;

    ALBEDO = col.rgb;
    ALPHA = col.a;
	
	if (VIEW_INDEX == VIEW_RIGHT)
		ALBEDO.g = 1.0;
}