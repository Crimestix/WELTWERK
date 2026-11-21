// Fluss als Band über dem Gelände (grobe Ausschnitte): klare, glatte Ränder in jedem Maßstab,
// mindestens so breit, dass er auf der Karte lesbar bleibt. Leicht zur Kamera versetzt, damit das
// Band nicht in den Rasterzellen des Geländes versinkt; Berge davor verdecken es weiterhin.
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

uniform vec3 center_color : source_color = vec3(0.07, 0.33, 0.47);
uniform vec3 edge_color : source_color = vec3(0.22, 0.58, 0.60);
// Versatz zur Kamera als Anteil des Kameraabstands.
uniform float lift = 0.0015;

varying float across;

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = cam - w;
	w += to_cam * lift;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	across = UV.x;
}

void fragment() {
	float d = min(across, 1.0 - across);
	float aa = max(fwidth(across) * 1.2, 0.001);
	float alpha = smoothstep(0.0, aa, d);
	float core = smoothstep(0.0, 0.5, d);
	ALBEDO = mix(edge_color, center_color, core);
	// Immer nach oben gewandt, gleich von welcher Seite das Band gesehen wird.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALPHA = alpha * 0.95;
	ROUGHNESS = 0.35;
	SPECULAR = 0.3;
}
