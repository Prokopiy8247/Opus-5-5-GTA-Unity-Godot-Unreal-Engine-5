shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Procedural facade shader for generated city blocks.
// UV  : x = metres along the wall perimeter, y = metres above the prism base
// UV2 : x = facade style id, y = per-building seed
// COLOR: facade base colour
global uniform float city_night;
global uniform float wetness;

uniform vec3 glass_day = vec3(0.16, 0.24, 0.32); // sRGB, converted with the rest of the albedo
uniform vec3 lit_warm : source_color = vec3(1.0, 0.78, 0.45);
uniform vec3 lit_cool : source_color = vec3(0.65, 0.85, 1.0);

// Colours in these shaders are authored in sRGB like every StandardMaterial3D albedo; convert before lighting.
vec3 to_lin(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
varying vec3 wnorm;
varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float style = floor(UV2.x + 0.5);
	float seed = UV2.y;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec3 albedo = base;
	// subtle large-scale variation so walls are not perfectly flat
	albedo *= 0.94 + 0.06 * hash(floor(wpos.xz * 0.25) + floor(wpos.y * 0.3));
	bool wall = abs(wnorm.y) < 0.5;
	// distance anti-aliasing: when a window cell shrinks below a few pixels the pattern is replaced
	// by its average (wall/glass mix and mean night glow), which removes moire on far facades.
	float far_mix = 0.0;
	float win_frac = 0.0;
	if (wall && style > 0.5) {
		float spacing = 3.0;
		float floor_h = 3.4;
		float ground = 0.0;
		float mx = 0.18;
		float my_lo = 0.28;
		float my_hi = 0.12;
		if (style > 0.5 && style < 1.5) { // office curtain wall
			spacing = 1.8; mx = 0.06; my_lo = 0.12; my_hi = 0.05; ground = 5.0;
		} else if (style > 1.5 && style < 2.5) { // apartment
			spacing = 3.2; mx = 0.24; my_lo = 0.3; my_hi = 0.18; ground = 3.6;
		} else if (style > 2.5 && style < 3.5) { // industrial clerestory strip
			spacing = 2.4; floor_h = 100.0; mx = 0.08; ground = 0.0;
		} else if (style > 3.5 && style < 4.5) { // shops / storefront ground floor + flats above
			spacing = 3.4; mx = 0.2; my_lo = 0.3; my_hi = 0.15; ground = 4.2;
		} else if (style > 4.5 && style < 5.5) { // house
			spacing = 3.6; mx = 0.32; my_lo = 0.35; my_hi = 0.25; ground = 0.0;
		}
		float v = UV.y;
		bool in_win = false;
		vec2 cell = vec2(0.0);
		if (style > 2.5 && style < 3.5) {
			// industrial: one horizontal clerestory band near the top of the wall
			float band = step(fract(seed * 7.0) * 2.0 + 5.0, v) * step(v, fract(seed * 7.0) * 2.0 + 6.4);
			vec2 c = vec2(UV.x / spacing, 0.0);
			far_mix = smoothstep(0.2, 0.5, fwidth(c.x)) * band;
			win_frac = 1.0 - 2.0 * mx;
			float fx = fract(c.x);
			in_win = band > 0.5 && fx > mx && fx < 1.0 - mx;
			cell = vec2(floor(c.x), 0.0);
		} else if (v > ground) {
			vec2 c = vec2(UV.x / spacing, (v - ground) / floor_h);
			vec2 f = fract(c);
			vec2 fw = fwidth(c);
			far_mix = smoothstep(0.16, 0.42, max(fw.x, fw.y));
			win_frac = (1.0 - 2.0 * mx) * (1.0 - my_lo - my_hi);
			in_win = f.x > mx && f.x < 1.0 - mx && f.y > my_lo && f.y < 1.0 - my_hi;
			cell = floor(c);
		} else if (ground > 0.5) {
			// storefront / lobby glazing on the ground floor
			float c = UV.x / 6.0;
			float fx = fract(c);
			in_win = fx > 0.06 && fx < 0.94 && v > 0.4 && v < ground - 0.9;
			cell = vec2(floor(c), -1.0);
			if (!in_win && v > ground - 0.8 && v < ground - 0.1) {
				// signage band
				albedo = mix(albedo, vec3(0.12, 0.12, 0.14), 0.7);
				emit += mix(lit_cool, vec3(1.0, 0.35, 0.55), step(0.5, hash(vec2(seed, 3.0)))) * city_night * 0.9;
			}
		}
		if (in_win) {
			float h = hash(cell + vec2(seed * 13.1, seed * 7.7));
			float frame_dark = 0.0;
			albedo = glass_day * (0.75 + 0.5 * h);
			rough = 0.08 + 0.1 * h;
			metal = 0.65;
			float lit_ratio = 0.55;
			if (style > 2.5 && style < 3.5) lit_ratio = 0.8;
			float lit = step(h, lit_ratio) * city_night;
			vec3 lc = mix(lit_warm, lit_cool, step(0.75, fract(h * 9.7)));
			emit += lc * lit * (0.9 + 1.4 * fract(h * 31.0));
			if (cell.y < -0.5) emit += lit_warm * city_night * 0.9;
		} else {
			// floor slab lines for depth
			if (style > 0.5 && style < 1.5 && v > ground) {
				float fy = fract((v - ground) / floor_h);
				albedo *= (fy < 0.06) ? 0.7 : 1.0;
			}
		}
		if (far_mix > 0.0) {
			float lr = (style > 2.5 && style < 3.5) ? 0.8 : 0.55;
			vec3 avg_alb = mix(base, glass_day, win_frac);
			albedo = mix(albedo, avg_alb, far_mix);
			rough = mix(rough, mix(0.85, 0.12, win_frac), far_mix);
			metal = mix(metal, 0.65 * win_frac, far_mix);
			vec3 avg_emit = mix(lit_warm, lit_cool, 0.25) * lr * 1.6 * city_night * win_frac;
			emit = mix(emit, avg_emit, far_mix);
		}
		if (v < 0.35) albedo *= 0.75; // dirt skirting
	} else if (!wall) {
		// roof: slightly darker with gravel noise
		albedo *= 0.78 + 0.1 * hash(floor(wpos.xz * 2.0));
		rough = 0.95;
	}
	// rain darkening / gloss
	float wet = wetness * (wall ? 0.5 : 1.0);
	albedo *= 1.0 - wet * 0.25;
	rough = mix(rough, rough * 0.35, wet);
	ALBEDO = to_lin(albedo);
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
