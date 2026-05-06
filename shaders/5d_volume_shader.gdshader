shader_type spatial;
render_mode unshaded, cull_front, blend_mix;

const int MAX_EXCLUSION_PLANES = 4;
const int MAX_STEPS = 256;
const float pi = 3.14159265359;

uniform sampler3D texture_volume : filter_linear, repeat_disable;
uniform int texture_mode = 1;
// 0 = scalar L8
// 1 = vector RGB
uniform float step_size = 0.005;
uniform float density = 1.0;
uniform float opacity = 1.0;
uniform float gamma = 1.0;
uniform float color_scalar = 1.0;
uniform float threshold = 0.0;

uniform float z_translucent : hint_range(0.0, 1.0) = 1.0;
uniform float orientation_gamma : hint_range(0.05, 5.0) = 1.0;

uniform int num_exclusion_planes = 0;
uniform vec4[MAX_EXCLUSION_PLANES] exclusion_planes;

varying vec3 local_pos;
varying vec3 local_camera_pos;

void vertex() {
	local_pos = VERTEX;
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

vec4 orientation_to_rgba(vec3 dir) {
	vec3 n = normalize(dir);

	float hue = atan(n.y, n.x) / (2.0 * PI) + 0.5;

	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(hue) + k) * 6.0 - 3.0);
	vec3 hue_rgb = clamp(p - 1.0, 0.0, 1.0);

	float az = pow(abs(n.z), orientation_gamma);
	vec3 pole_color = n.z >= 0.0 ? vec3(1.0) : vec3(0.0);

	vec3 rgb = mix(hue_rgb, pole_color, az * z_translucent);
	float alpha = mix(1.0, 0.5 * z_translucent, az);

	return vec4(rgb, alpha);
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

		vec3 uvw = p + vec3(0.5);

		if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) {
			t += step_size;
			continue;
		}

		vec4 tex = texture(texture_volume, uvw);

		vec3 sample_rgb;
		float sample_alpha;

		if (texture_mode == 0) {
			// Scalar mode: magnitude/mx/my/mz uploaded as grayscale.
			float value = tex.r;

			if (value < threshold) {
				t += step_size;
				continue;
			}

			value = pow(value, gamma);

			sample_rgb = vec3(value);
			sample_alpha = value * opacity * density;
		} else {
			// Vector RGB mode: mx,my,mz uploaded into RGB.
			vec3 packed_rgb = tex.rgb;
			vec3 dir = packed_rgb * 2.0 - vec3(1.0);

			float strength = length(dir);

			if (strength < threshold) {
				t += step_size;
				continue;
			}

			float normalized_strength = clamp(strength / 1.7320508, 0.0, 1.0);
			normalized_strength = pow(normalized_strength, gamma);

			vec4 orient_col = orientation_to_rgba(dir);

			sample_rgb = orient_col.rgb;
			sample_alpha = orient_col.a * normalized_strength * opacity * density;
		}

		float remaining = 1.0 - total_alpha;
		accumulated.rgb += sample_rgb * sample_alpha * remaining;
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