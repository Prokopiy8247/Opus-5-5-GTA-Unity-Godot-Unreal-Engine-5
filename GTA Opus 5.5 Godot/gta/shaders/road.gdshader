shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Asphalt with procedural lane markings.
// UV.x  : metres across the road from the centre line (negative = left)
// UV.y  : metres along the segment
// UV2.x : lanes per direction (0 = plain asphalt / intersection, 1, 2, 9 = runway)
// UV2.y : segment length in metres (crosswalks are drawn near both ends when > 0)
// COLOR.r: road half width / 20
global uniform float wetness;
global uniform float city_night;

// Colours in these shaders are authored in sRGB like every StandardMaterial3D albedo; convert before lighting.
vec3 to_lin(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = UV.x;
	float s = UV.y;
	float lanes = floor(UV2.x + 0.5);
	float len = UV2.y;
	float hw = COLOR.r * 20.0;
	float n = vnoise(wpos.xz * 0.35) * 0.6 + vnoise(wpos.xz * 2.1) * 0.4;
	vec3 asphalt = vec3(0.3, 0.305, 0.33) * (0.86 + 0.24 * n);
	// patches / oil stains
	float patchy = vnoise(wpos.xz * 0.05 + 17.0);
	asphalt *= mix(1.0, 0.8, smoothstep(0.72, 0.8, patchy));
	float oil = smoothstep(0.78, 0.86, vnoise(wpos.xz * 0.6 + 3.0)) * 0.35;
	asphalt *= 1.0 - oil;
	// cracks
	float crack = smoothstep(0.02, 0.0, abs(vnoise(wpos.xz * 0.7) - 0.5)) * 0.25;
	asphalt *= 1.0 - crack;
	vec3 col = asphalt;
	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	float ax = abs(x);
	if (lanes > 0.5 && lanes < 8.5) {
		bool near_end = len > 0.0 && (s < 5.0 || s > len - 5.0);
		// centre double yellow (or median strip for 2 lanes)
		if (lanes < 1.5) {
			if (ax > 0.08 && ax < 0.22) { paint = 1.0; paint_col = vec3(0.95, 0.75, 0.18); }
		} else {
			if (ax < 0.5) { col = vec3(0.55, 0.54, 0.5); }
			if (ax > 0.5 && ax < 0.64) { paint = 1.0; paint_col = vec3(0.95, 0.75, 0.18); }
			// lane separator dashes
			float lx = abs(ax - 0.5 - 3.5);
			if (lx < 0.07 && fract(s / 9.0) < 0.45 && !near_end) paint = 1.0;
		}
		// edge lines
		if (abs(ax - (hw - 0.35)) < 0.08) paint = 1.0;
		if (near_end) {
			float d_end = min(s, len - s);
			// zebra crossing
			if (d_end < 3.6 && d_end > 0.4 && fract(x / 1.1) < 0.55 && ax < hw - 0.5) { paint = 1.0; paint_col = vec3(0.95); }
			// stop line on the incoming half (right-hand traffic)
			bool incoming = (s > len * 0.5) ? (x > 0.0) : (x < 0.0);
			if (incoming && d_end > 3.9 && d_end < 4.35 && ax < hw - 0.4 && ax > 0.3) { paint = 1.0; paint_col = vec3(0.95); }
		}
	} else if (lanes > 8.5) {
		// runway: centreline dashes, threshold bars, edge lines
		if (ax < 0.45 && fract(s / 30.0) < 0.5) paint = 1.0;
		if (abs(ax - (hw - 1.0)) < 0.3) paint = 1.0;
		if ((s < 30.0 || s > len - 30.0) && s > 4.0 && s < len - 4.0 && fract(x / 3.0) < 0.5 && ax < hw - 2.0 && (s < 26.0 || s > len - 26.0)) paint = 1.0;
	}
	float wear = 0.65 + 0.35 * vnoise(wpos.xz * 1.7);
	col = mix(col, paint_col * wear, paint);
	// wet look + puddles
	float puddle = smoothstep(0.55, 0.7, vnoise(wpos.xz * 0.18 + 9.0)) * wetness;
	float wet = clamp(wetness * 0.7 + puddle, 0.0, 1.0);
	col *= 1.0 - wet * 0.35;
	ALBEDO = to_lin(col);
	ROUGHNESS = mix(0.9 - paint * 0.2, 0.08, wet);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.8, wet);
}
