shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// Stylised ocean: depth-tinted, refracting, shoreline foam, animated normals.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform float city_night;
global uniform float wetness;

uniform vec3 shallow_col : source_color = vec3(0.12, 0.62, 0.66);
uniform vec3 deep_col : source_color = vec3(0.02, 0.16, 0.3);
uniform vec3 foam_col : source_color = vec3(0.92, 0.97, 1.0);
uniform float wave_speed = 0.6;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 wpos;

float height_at(vec2 p, float t) {
	float h = sin(p.x * 0.11 + t * 1.1) * 0.5 + sin(p.y * 0.07 - t * 0.8) * 0.5;
	h += (vnoise(p * 0.35 + vec2(t * 0.6, t * 0.3)) - 0.5) * 1.2;
	h += (vnoise(p * 1.3 - vec2(t * 0.9, -t * 0.4)) - 0.5) * 0.45;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = wpos.xz;
	float e = 0.25;
	float hc = height_at(p, t);
	float hx = height_at(p + vec2(e, 0.0), t);
	float hz = height_at(p + vec2(0.0, e), t);
	float storm = 1.0 + wetness * 1.5;
	vec3 nrm_w = normalize(vec3(-(hx - hc) * 0.22 * storm, 1.0, -(hz - hc) * 0.22 * storm));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_w, 0.0)).xyz);

	// scene depth behind the water surface
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vpos.xyz /= vpos.w;
	float scene_d = -vpos.z;
	float surf_d = -VERTEX.z;
	float thickness = max(scene_d - surf_d, 0.0);

	if (FRONT_FACING) {
		float depth_f = clamp(thickness / 9.0, 0.0, 1.0);
		vec3 water = mix(shallow_col, deep_col, depth_f);
		// refraction
		vec2 off = nrm_w.xz * 0.025 * clamp(thickness, 0.0, 1.0);
		vec3 refr = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
		float clarity = exp(-thickness * 0.35);
		vec3 col = mix(water, refr * mix(vec3(1.0), shallow_col * 1.4, 0.4), clarity * 0.75);
		// shoreline foam
		float foam_n = vnoise(p * 1.6 + vec2(t * 0.8, 0.0));
		float foam = smoothstep(0.9, 0.0, thickness) * smoothstep(0.25, 0.65, foam_n + (1.0 - thickness) * 0.4);
		foam += smoothstep(0.8, 0.95, hc * 0.5 + 0.5) * 0.25 * storm;
		col = mix(col, foam_col, clamp(foam, 0.0, 1.0));
		ALBEDO = col * (1.0 - city_night * 0.55);
		ROUGHNESS = 0.04 + foam * 0.5;
		METALLIC = 0.1;
		SPECULAR = 0.7;
		ALPHA = clamp(0.88 + foam * 0.12, 0.0, 1.0);
	} else {
		// seen from below
		ALBEDO = shallow_col * 0.6;
		ROUGHNESS = 0.2;
		ALPHA = 0.55;
	}
}
