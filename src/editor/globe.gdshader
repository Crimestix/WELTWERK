// Globus: Meer, Breitengrade und der platzierte Kontinent (aus seinem Kontinentbild).
// Lage wie GlobeMath: mittabstandstreue Abbildung um (lat0, lon0), gedreht um heading.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D continent_color : source_color, filter_linear, repeat_disable;
uniform sampler2D continent_data : filter_linear, repeat_disable;  // R = Höhe (m)
uniform float lat0 = 35.0;
uniform float lon0 = 10.0;
uniform float heading = 0.0;
uniform float size_m = 800000.0;
uniform float planet_radius_m = 6371000.0;
uniform float relief_scale = 0.0; // Darstellungseinheiten je Meter Höhe
uniform bool highlight = true;

uniform vec3 deep_color : source_color = vec3(0.03, 0.12, 0.25);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.42, 0.48);
uniform vec3 line_color : source_color = vec3(0.85, 0.80, 0.65);
uniform vec3 outline_color : source_color = vec3(0.88, 0.70, 0.38);

varying vec3 model_dir;

vec2 continent_uv(vec3 dir) {
	vec3 n = normalize(dir);
	float phi = asin(clamp(n.y, -1.0, 1.0));
	float lam = atan(n.x, n.z);
	float phi0 = radians(lat0);
	float dlam = lam - radians(lon0);
	float cos_c = clamp(sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(dlam), -1.0, 1.0);
	float c = acos(cos_c);
	float k = c < 1e-6 ? 1.0 : c / sin(c);
	float e = planet_radius_m * k * cos(phi) * sin(dlam);
	float no = planet_radius_m * k * (cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(dlam));
	float h = radians(heading);
	float x = e * cos(h) - no * sin(h);
	float y = e * sin(h) + no * cos(h);
	if (cos_c < 0.0) {
		return vec2(-1.0); // Rückseite
	}
	return vec2(x / size_m + 0.5, 0.5 - y / size_m);
}

bool inside(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

void vertex() {
	model_dir = VERTEX;
	vec2 uv = continent_uv(VERTEX);
	if (inside(uv)) {
		float h = textureLod(continent_data, uv, 0.0).r;
		VERTEX += normalize(VERTEX) * max(h, 0.0) * relief_scale;
	}
}

void fragment() {
	vec3 n = normalize(model_dir);
	float lat = degrees(asin(clamp(n.y, -1.0, 1.0)));
	vec3 c = deep_color;
	vec2 uv = continent_uv(model_dir);
	float rough = 0.55;
	if (inside(uv)) {
		vec4 col = texture(continent_color, uv);
		float h = texture(continent_data, uv).r;
		vec3 sea = mix(shallow_color, deep_color, smoothstep(-20.0, -600.0, h));
		c = mix(sea, col.rgb, col.a);
		rough = mix(0.55, 0.9, col.a);
		if (highlight) {
			vec2 edge = min(uv, 1.0 - uv);
			float frame = 1.0 - smoothstep(0.0, 0.006, min(edge.x, edge.y));
			c = mix(c, outline_color, frame * 0.6);
		}
	}
	// Breitengrade: Äquator kräftig, 30° und 60° fein.
	float px = fwidth(lat) * 1.2;
	float equator = 1.0 - smoothstep(0.0, px * 1.5, abs(lat));
	float grid = 0.0;
	for (int k = -2; k <= 2; k++) {
		if (k == 0) continue;
		grid = max(grid, 1.0 - smoothstep(0.0, px, abs(lat - float(k) * 30.0)));
	}
	c = mix(c, line_color, max(equator * 0.8, grid * 0.45));
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
