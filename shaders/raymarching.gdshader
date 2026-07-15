shader_type spatial;
render_mode unshaded, cull_front;

const int MAX_EXCLUSION_PLANES = 4;
// Opacity is calibrated against this step size; changing step_size only
// changes quality, not the rendered density.
const float REFERENCE_STEP = 0.005;

uniform int max_steps = 256;
uniform float step_size = 0.005;

uniform sampler3D texture_volume : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D gradient : filter_linear_mipmap, repeat_disable;
uniform float zoom = 2.0;
uniform float opacity = 1.0;
uniform float gamma = 1.0;
uniform float color_scalar = 1.0;
uniform int num_exclusion_planes = 0;
// Planes in object (mesh-local) space; kept region is dot(p, xyz) <= w.
uniform vec4[MAX_EXCLUSION_PLANES] exclusion_planes;

uniform bool shading_enabled = false;
// Light direction in object space.
uniform vec3 light_dir = vec3(0.5, 0.7, 0.5);
uniform float ambient = 0.4;

varying vec3 pos_local;
varying vec3 eye_pos_local;


void vertex() {
	pos_local = VERTEX;

	// Per-eye world-space camera position, brought into object space so the
	// fragment shader needs no matrix inverses.
	vec3 eye_world = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
	eye_pos_local = (inverse(MODEL_MATRIX) * vec4(eye_world, 1.0)).xyz;
}


// Clip the ray interval [t_near, t_far] to an axis-aligned box of the given
// half extents centered at the origin.
void clip_to_box(vec3 ro, vec3 rd, vec3 half_extents, inout float t_near, inout float t_far) {
	vec3 t_a = (-half_extents - ro) / rd;
	vec3 t_b = ( half_extents - ro) / rd;
	vec3 t_lo = min(t_a, t_b);
	vec3 t_hi = max(t_a, t_b);
	t_near = max(t_near, max(max(t_lo.x, t_lo.y), t_lo.z));
	t_far = min(t_far, min(min(t_hi.x, t_hi.y), t_hi.z));
}


// Estimate the volume-density normal via central differences, in texture space.
vec3 density_normal(vec3 uvw) {
	vec3 eps = 1.0 / vec3(textureSize(texture_volume, 0));
	float dx = texture(texture_volume, uvw + vec3(eps.x, 0.0, 0.0)).r
	         - texture(texture_volume, uvw - vec3(eps.x, 0.0, 0.0)).r;
	float dy = texture(texture_volume, uvw + vec3(0.0, eps.y, 0.0)).r
	         - texture(texture_volume, uvw - vec3(0.0, eps.y, 0.0)).r;
	float dz = texture(texture_volume, uvw + vec3(0.0, 0.0, eps.z)).r
	         - texture(texture_volume, uvw - vec3(0.0, 0.0, eps.z)).r;
	return vec3(dx, dy, dz);
}


void fragment() {
	vec3 ro = eye_pos_local;
	vec3 rd = normalize(pos_local - eye_pos_local);

	// Clip the ray to the mesh box and to the region where texture
	// coordinates are in [0, 1] (they differ when zoom != 2).
	float t_near = 0.0;
	float t_far = 1e20;
	clip_to_box(ro, rd, vec3(0.5), t_near, t_far);
	clip_to_box(ro, rd, vec3(1.0 / zoom), t_near, t_far);

	// The kept region of the exclusion planes (dot <= w for every plane) is
	// convex, so it clips the interval exactly — no per-step tests needed.
	for (int i = 0; i < num_exclusion_planes; ++i) {
		vec4 plane = exclusion_planes[i];
		float denom = dot(rd, plane.xyz);
		float dist = plane.w - dot(ro, plane.xyz);
		if (abs(denom) < 1e-6) {
			if (dist < 0.0)
				t_far = -1.0; // origin excluded, ray parallel: nothing kept
		} else if (denom > 0.0) {
			t_far = min(t_far, dist / denom);
		} else {
			t_near = max(t_near, dist / denom);
		}
	}

	if (t_far <= t_near)
		discard;

	// Jitter the ray start (interleaved gradient noise) to break up the
	// banding of fixed-step sampling.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));

	// Opacity correction keeps density independent of step size.
	float step_ratio = step_size / REFERENCE_STEP;
	vec3 accumulated_color = vec3(0.0);
	float total_opacity = 0.0;

	for (int i = 0; i < max_steps; ++i) {
		float t = t_near + (float(i) + jitter) * step_size;
		if (t > t_far)
			break;

		vec3 ray_pos = ro + rd * t;
		vec3 tex_sample_pt = ((ray_pos * zoom) / 2.0) + vec3(0.5);

		float density = texture(texture_volume, tex_sample_pt).r;
		vec4 sample = texture(gradient, vec2(pow(density, gamma), 0.5));

		float sample_opacity = 1.0 - pow(1.0 - clamp(sample.a * opacity, 0.0, 1.0), step_ratio);

		if (shading_enabled && sample_opacity > 0.001) {
			vec3 n = density_normal(tex_sample_pt);
			if (dot(n, n) > 1e-8) {
				float diffuse = max(dot(normalize(n), normalize(light_dir)), 0.0);
				sample.rgb *= ambient + (1.0 - ambient) * diffuse;
			}
		}

		accumulated_color += sample.rgb * sample_opacity * (1.0 - total_opacity);
		total_opacity += sample_opacity * (1.0 - total_opacity);

		if (total_opacity >= 0.95)
			break;
	}

	ALBEDO = accumulated_color * color_scalar;
	ALPHA = total_opacity;
}
