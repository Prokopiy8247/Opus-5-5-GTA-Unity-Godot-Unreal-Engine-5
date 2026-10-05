shader_type sky;
render_mode use_debanding;

// Gradient sky with sun, moon, stars and procedural cloud deck (driven by EnvController).
uniform vec3 top_color : source_color = vec3(0.22, 0.44, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.78, 0.7);
uniform vec3 ground_color : source_color = vec3(0.2, 0.24, 0.28);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.75, 0.45);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 sun_dir_u = vec3(0.3, 0.8, 0.3);
uniform vec3 sun_disk_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.94);
uniform vec3 cloud_dark : source_color = vec3(0.55, 0.58, 0.66);
uniform float star_strength = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float exposure = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * a;
		p = p * 2.07 + vec2(13.1, 7.3);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col;
	if (d.y >= 0.0) {
		float t = pow(1.0 - d.y, 3.2);
		col = mix(top_color, horizon_color, t);
	} else {
		col = mix(horizon_color, ground_color, clamp(-d.y * 5.0, 0.0, 1.0));
	}
	vec3 sun_dir = normalize(sun_dir_u);
	float sun_vis = smoothstep(-0.12, 0.1, sun_dir.y);
	{
		float sd = dot(d, sun_dir);
		col += sun_glow * pow(max(sd, 0.0), 12.0) * 0.35 * sun_vis;
		col += sun_glow * pow(max(sd, 0.0), 120.0) * 0.6 * sun_vis;
		float disk = smoothstep(0.9993, 0.9996, sd);
		col = mix(col, sun_disk_color * 5.0, disk * sun_vis * (1.0 - cloud_cover * 0.8));
	}
	// stars + moon
	if (star_strength > 0.001 && d.y > 0.0) {
		vec2 sp = d.xz / (d.y + 0.3) * 160.0;
		float s = hash(floor(sp));
		float star = step(0.9965, s) * smoothstep(0.6, 0.0, length(fract(sp) - 0.5));
		col += vec3(star) * star_strength * (1.0 - cloud_cover);
		float md = dot(d, normalize(moon_dir));
		col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9985, 0.9992, md) * star_strength * 1.8;
		col += vec3(0.3, 0.38, 0.55) * pow(max(md, 0.0), 30.0) * star_strength * 0.35;
	}
	// clouds
	if (d.y > 0.0) {
		vec2 cp = d.xz / (d.y + 0.12) * 1.6 + cloud_offset;
		float n = fbm(cp);
		float cov = mix(0.75, 0.25, cloud_cover);
		float c = smoothstep(cov, cov + 0.22, n) * smoothstep(0.0, 0.18, d.y);
		float lit = clamp(dot(normalize(vec3(cp.x, 1.0, cp.y) * 0.0 + sun_dir), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0);
		vec3 cc = mix(cloud_dark, cloud_lit, clamp(fbm(cp * 1.7 + 5.0) * 1.2 + 0.1, 0.0, 1.0));
		cc = mix(cc, cc * horizon_color * 1.3, (1.0 - d.y) * 0.35);
		col = mix(col, cc * (0.35 + 0.65 * sun_vis) + horizon_color * 0.1 * (1.0 - sun_vis), c * (0.6 + 0.4 * cloud_cover));
		col += sun_glow * pow(max(dot(d, sun_dir), 0.0), 8.0) * c * 0.3 * sun_vis * lit;
	}
	COLOR = col * exposure;
}
