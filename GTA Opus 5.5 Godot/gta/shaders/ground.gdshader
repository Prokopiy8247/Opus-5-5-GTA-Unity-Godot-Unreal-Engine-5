shader_type spatial;
render_mode diffuse_burley;

// Flat ground covers. UV2.x selects the pattern:
// 0 sidewalk pavers, 1 grass, 2 parking asphalt (with bay lines), 3 sand, 4 wood planks, 5 plaza tiles,
// 6 concrete apron, 7 gravel/dirt, 8 curb (plain concrete), 9 helipad
// UV = world-space metres. COLOR = tint.
global uniform float wetness;
global uniform float city_night;

// Colours in these shaders are authored in sRGB like every StandardMaterial3D albedo; convert before lighting.
vec3 to_lin(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float kind = floor(UV2.x + 0.5);
	vec2 p = wpos.xz;
	vec3 c = COLOR.rgb;
	float rough = 0.9;
	float n = vnoise(p * 0.8) * 0.6 + vnoise(p * 5.0) * 0.4;
	if (kind < 0.5) {
		vec2 g = fract(p / 1.5);
		float joint = step(g.x, 0.04) + step(g.y, 0.04);
		c = vec3(0.64, 0.63, 0.6) * (0.88 + 0.2 * n) * (1.0 - clamp(joint, 0.0, 1.0) * 0.25);
	} else if (kind < 1.5) {
		c = mix(vec3(0.33, 0.55, 0.24), vec3(0.45, 0.66, 0.3), vnoise(p * 0.3)) * (0.85 + 0.3 * n);
		rough = 1.0;
	} else if (kind < 2.5) {
		c = vec3(0.3, 0.305, 0.32) * (0.85 + 0.3 * n);
		vec2 g = vec2(fract(p.x / 2.7), fract(p.y / 5.4));
		float line = step(g.x, 0.04) * step(0.15, g.y) * step(g.y, 0.85);
		c = mix(c, vec3(0.85), line);
	} else if (kind < 3.5) {
		c = vec3(0.86, 0.75, 0.55) * (0.9 + 0.15 * n) * (0.95 + 0.05 * sin(p.x * 3.0 + vnoise(p) * 6.0));
		rough = 1.0;
	} else if (kind < 4.5) {
		float plank = fract(p.x / 0.3);
		float id = floor(p.x / 0.3);
		c = vec3(0.52, 0.36, 0.22) * (0.75 + 0.35 * hash(vec2(id, floor(p.y / 4.0 + hash(vec2(id))))));
		c *= 1.0 - step(plank, 0.06) * 0.5;
		c *= 0.9 + 0.2 * vnoise(vec2(p.x * 2.0, p.y * 0.2));
	} else if (kind < 5.5) {
		vec2 g = fract(p / 2.0);
		vec2 id = floor(p / 2.0);
		float checker = mod(id.x + id.y, 2.0);
		c = mix(vec3(0.66, 0.6, 0.53), vec3(0.56, 0.44, 0.38), checker * 0.6) * (0.9 + 0.15 * n);
		c *= 1.0 - (step(g.x, 0.03) + step(g.y, 0.03)) * 0.2;
	} else if (kind < 6.5) {
		vec2 g = fract(p / 6.0);
		c = vec3(0.56, 0.56, 0.54) * (0.85 + 0.25 * n) * (1.0 - (step(g.x, 0.01) + step(g.y, 0.01)) * 0.3);
	} else if (kind < 7.5) {
		c = vec3(0.5, 0.43, 0.34) * (0.8 + 0.4 * n);
		rough = 1.0;
	} else if (kind < 8.5) {
		c = vec3(0.7, 0.69, 0.66) * (0.9 + 0.15 * n);
	} else {
		c = vec3(0.36, 0.38, 0.41) * (0.9 + 0.2 * n);
		vec2 q = (p - UV) ; // UV holds local centre offset for helipads
		vec2 l = UV;
		float r = length(l);
		float ring = step(abs(r - 7.0), 0.35);
		float hbar = step(abs(l.x), 3.0) * step(abs(l.y), 0.5);
		float hside = step(abs(abs(l.x) - 2.6), 0.4) * step(abs(l.y), 3.6);
		c = mix(c, vec3(0.95, 0.85, 0.2), ring);
		c = mix(c, vec3(0.95), clamp(hbar + hside, 0.0, 1.0));
	}
	c *= COLOR.rgb;
	float wet = wetness * (kind > 0.5 && kind < 1.5 ? 0.3 : 0.8);
	ALBEDO = to_lin(c * (1.0 - wet * 0.3));
	ROUGHNESS = mix(rough, 0.2, wet);
}
