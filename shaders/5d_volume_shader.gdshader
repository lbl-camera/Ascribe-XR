shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

const int MAX_EXCLUSION_PLANES = 4;
const int MAX_STEPS = 256;

uniform sampler3D texture_volume : filter_linear, repeat_disable;
uniform sampler2D gradient : filter_linear, repeat_disable;

uniform float step_size = 0.005;
uniform float density = 1.0;
uniform float opacity = 1.0;
uniform float gamma = 1.0;
uniform float color_scalar = 1.0;
uniform float threshold = 0.0;

uniform int num_exclusion_planes = 0;
uniform vec4[MAX_EXCLUSION_PLANES] exclusion_planes;

varying vec3 local_pos;
varying vec3 local_camera_pos;

void vertex() {
	local_pos = VERTEX;

	// Camera position in object/local space.
	local_camera_pos = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

bool is_outside_exclusion_planes(vec3 point) {
	for (int i = 0; i < MAX_EXCLUSION_PLANES; i++) {
		if (i >= num_exclusion_planes) {
			break;
		}

		vec4 plane = exclusion_planes[i];

		if (dot(point, plane.xyz) > plane.w) {
			return true;
		}
	}

	return false;
}

bool intersect_box(
	vec3 ray_origin,
	vec3 ray_dir,
	vec3 box_min,
	vec3 box_max,
	out float t_entry,
	out float t_exit
) {
	vec3 inv_dir = 1.0 / ray_dir;

	vec3 t0 = (box_min - ray_origin) * inv_dir;
	vec3 t1 = (box_max - ray_origin) * inv_dir;

	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);

	t_entry = max(max(tmin.x, tmin.y), tmin.z);
	t_exit = min(min(tmax.x, tmax.y), tmax.z);

	return t_exit >= max(t_entry, 0.0);
}

vec4 raymarch(vec3 ray_origin, vec3 ray_dir, float t_start, float t_end) {
	vec4 accumulated = vec4(0.0);
	float total_alpha = 0.0;

	float t = max(t_start, 0.0);

	for (int i = 0; i < MAX_STEPS; i++) {
		if (t > t_end) {
			break;
		}

		vec3 p = ray_origin + ray_dir * t;

		if (is_outside_exclusion_planes(p)) {
			t += step_size;
			continue;
		}

		// Object-space cube is assumed to be -0.5 to +0.5.
		vec3 uvw = p + vec3(0.5);

		if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) {
			t += step_size;
			continue;
		}

		float value = texture(texture_volume, uvw).r;

		if (value < threshold) {
			t += step_size;
			continue;
		}

		value = pow(value, gamma);

		vec4 sample_col = texture(gradient, vec2(value, 0.5));

		float sample_alpha = sample_col.a * opacity * density;

		// Front-to-back alpha compositing.
		float remaining = 1.0 - total_alpha;
		accumulated.rgb += sample_col.rgb * sample_alpha * remaining;
		total_alpha += sample_alpha * remaining;

		if (total_alpha >= 0.98) {
			break;
		}

		t += step_size;
	}

	accumulated.a = total_alpha;
	return accumulated;
}

void fragment() {
	vec3 ro = local_camera_pos;
	vec3 rd = normalize(local_pos - local_camera_pos);

	vec3 box_min = vec3(-0.5);
	vec3 box_max = vec3(0.5);

	float t_entry;
	float t_exit;

	if (!intersect_box(ro, rd, box_min, box_max, t_entry, t_exit)) {
		discard;
	}

	vec4 col = raymarch(ro, rd, t_entry, t_exit);

	col.rgb *= color_scalar;

	ALBEDO = col.rgb;
	ALPHA = col.a;

	if (ALPHA <= 0.001) {
		discard;
	}
}