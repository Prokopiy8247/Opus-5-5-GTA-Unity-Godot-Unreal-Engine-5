shader_type spatial;
render_mode diffuse_burley;

// Terrain / ground: vertex colour carries the biome tint, detail noise breaks up flat areas.
global uniform float wetness;

// Colours in these shaders are authored in sRGB like every StandardMaterial3D albedo; convert before lighting.
vec3 to_lin(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float n = vnoise(wpos.xz * 0.15) * 0.5 + vnoise(wpos.xz * 0.9) * 0.3 + vnoise(wpos.xz * 4.0) * 0.2;
	c *= 0.85 + 0.3 * n;
	// steep faces become rock
	float steep = smoothstep(0.75, 0.55, wnorm.y);
	c = mix(c, vec3(0.42, 0.4, 0.38) * (0.8 + 0.4 * n), steep);
	// underwater darkening (caustic-ish banding)
	float under = smoothstep(0.2, -2.0, wpos.y);
	c = mix(c, c * vec3(0.55, 0.75, 0.8), under);
	float wet = wetness * (1.0 - under) * 0.6;
	ALBEDO = to_lin(c * (1.0 - wet * 0.3));
	ROUGHNESS = mix(0.95, 0.4, wet);
}
