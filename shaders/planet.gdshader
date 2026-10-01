shader_type canvas_item;

// Planete vue du cockpit : sphere ombree, motif procedural selon le type,
// quadrillage neon (lat/long) et halo d'atmosphere.

uniform vec2 rect_size = vec2(900.0, 600.0);
uniform vec2 center = vec2(450.0, 300.0);
uniform float radius = 100.0;
uniform vec4 color_a : source_color = vec4(0.1, 0.2, 0.5, 1.0);
uniform vec4 color_b : source_color = vec4(0.2, 0.6, 0.4, 1.0);
uniform vec4 atmo : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform vec4 line_color : source_color = vec4(0.2, 0.95, 1.0, 1.0);
uniform int style = 1;
uniform float spin = 0.0;
uniform float seed = 0.0;
uniform float alpha = 1.0;
uniform float grid_amount = 0.5;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 d = (px - center) / radius;
	float l = length(d);
	float aa = 1.5 / radius;
	vec3 col = vec3(0.0);
	float a = 0.0;

	if (l < 1.0 + aa) {
		float lc = min(l, 1.0);
		float z = sqrt(max(1.0 - lc * lc, 0.0));
		vec3 n = vec3(d.x, d.y, z) / max(length(vec3(d.x, d.y, z)), 0.0001);
		float cs = cos(spin);
		float sn = sin(spin);
		vec3 nr = vec3(n.x * cs - n.z * sn, n.y, n.x * sn + n.z * cs);
		vec3 q = nr * 2.5 + vec3(seed);

		float v;
		if (style == 0) {
			v = 0.5 + 0.5 * sin(nr.y * 16.0 + fbm3(q) * 5.0);
		} else if (style == 2) {
			v = 0.5 + 0.5 * sin(nr.x * 18.0 + nr.y * 6.0 + fbm3(q * 1.5) * 6.0);
			v = mix(v, fbm3(q * 2.0), 0.4);
		} else {
			v = smoothstep(0.46, 0.56, fbm3(q));
		}
		vec3 base = mix(color_a.rgb, color_b.rgb, v);

		vec3 light = normalize(vec3(-0.55, -0.45, 0.7));
		float lambert = clamp(dot(n, light), 0.0, 1.0);
		col = base * (0.1 + 0.9 * lambert);
		col += atmo.rgb * pow(1.0 - z, 3.0) * (0.35 + 0.9 * lambert);

		// Quadrillage neon lat/long (esthetique vectorielle).
		float lon = atan(nr.x, nr.z);
		float lat = asin(clamp(nr.y, -1.0, 1.0));
		// Epaisseur constante en pixels, quelle que soit la taille de la planete a l'ecran.
		float xlon = lon / 6.2831853 * 16.0;
		float xlat = lat / 3.1415926 * 9.0;
		float dlon = abs(fract(xlon + 0.5) - 0.5) / max(fwidth(xlon), 0.0001);
		float dlat = abs(fract(xlat + 0.5) - 0.5) / max(fwidth(xlat), 0.0001);
		float g = max(1.0 - smoothstep(0.5, 1.6, dlon), 1.0 - smoothstep(0.5, 1.6, dlat));
		col += line_color.rgb * g * grid_amount * (0.3 + 0.7 * lambert);

		// Liseré neon sur le bord.
		col += line_color.rgb * (1.0 - smoothstep(0.0, 3.0 / radius, abs(l - 1.0))) * 0.8;
		a = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, l);
	}

	// Halo d'atmosphere a l'exterieur du disque.
	float halo = exp(-max(l - 1.0, 0.0) * 7.0) * step(1.0 - aa, l) * 0.55;
	col = mix(atmo.rgb, col, a);
	a = max(a, halo);
	COLOR = vec4(col, a * alpha);
}
