shader_type canvas_item;

// Fond de la vue cockpit : nebuleuse de la region traversee + tunnel d'hyperespace.
// `travel` est la distance parcourue cumulee (integree cote CPU, suit la vitesse).

uniform vec2 rect_size = vec2(900.0, 600.0);
uniform vec2 vp = vec2(450.0, 235.0);
uniform float travel = 0.0;
uniform float intensity = 1.0;
uniform float roll = 0.0;
uniform float flash = 0.0;
uniform vec4 color_a : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform vec4 space_color : source_color = vec4(0.01, 0.01, 0.03, 1.0);
uniform vec4 nebula_color : source_color = vec4(0.3, 0.2, 0.5, 1.0);
uniform float nebula_amount = 0.5;
uniform float nebula_drift = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * rect_size;
	float m = min(rect_size.x, rect_size.y);
	vec2 p = (px - vp) / m;
	float cr = cos(roll);
	float sr = sin(roll);
	p = vec2(cr * p.x - sr * p.y, sr * p.x + cr * p.y);
	float r = length(p);
	float ang = atan(p.y, p.x);

	// Nebuleuse : deux couches de bruit, teintees par la region.
	vec2 np = p * 1.4 + vec2(nebula_drift, nebula_drift * 0.3);
	float n1 = smoothstep(0.42, 0.95, fbm(np * 2.2 + 7.0));
	float n2 = smoothstep(0.5, 1.0, fbm(np * 4.5 - 3.0));
	vec3 col = space_color.rgb;
	col += nebula_color.rgb * (n1 * 0.55 + n2 * 0.3) * nebula_amount;

	// Tunnel : des "couloirs" angulaires ou defilent des trainees lumineuses.
	float depth = 0.11 / max(r, 0.0015);
	float z = depth + travel;
	const float LANES = 96.0;
	float fa = (ang / 6.2831853 + 0.5) * LANES;
	float cell = floor(fa);
	float h = hash11(cell);
	float h2 = hash11(cell + 17.0);
	float across = abs(fract(fa) - 0.5) * 2.0;
	float lane = 1.0 - smoothstep(0.1, 0.55 + 0.35 * h, across);
	float seg = fract(z * (0.18 + 0.4 * h2) + h * 7.0);
	float streak = smoothstep(0.0, 0.04, seg) * (1.0 - smoothstep(0.04, 0.5 + 0.45 * h, seg));
	streak *= lane * step(0.3, h);
	float near = smoothstep(0.015, 0.45, r);
	vec3 sc = mix(color_a.rgb, color_b.rgb, h2);
	vec3 tunnel = sc * streak * near * 1.7;

	// Parois du tunnel : ondulation lente, plus lumineuse vers les bords.
	float wall = 0.5 + 0.5 * sin(z * 3.0 + ang * 3.0 + sin(ang * 5.0 + travel * 0.05));
	vec3 wc = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * sin(ang * 2.0 + travel * 0.02));
	tunnel += wc * wall * 0.16 * near * near;
	// Coeur blanc au point de fuite.
	tunnel += vec3(0.85, 0.92, 1.0) * exp(-r * 13.0) * 1.3;

	col = col * (1.0 - 0.7 * intensity) + tunnel * intensity;
	col += vec3(flash);
	COLOR = vec4(col, 1.0);
}
