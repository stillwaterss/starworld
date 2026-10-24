shader_type spatial;
// Soft, lobed cloud puff on a camera-facing quad: fbm density with a round falloff,
// brighter tops and a faint warm rim toward the sun, tinted by the day/dusk/night blend.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec3 time_weights = vec3(0.0, 0.0, 1.0);
uniform float seed = 0.0;
uniform float softness = 1.0;
uniform float flatness = 0.55;     // 1 round puff, lower = long low bank
uniform float opacity = 0.9;
varying float fade_far;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void vertex() {
	// billboard that keeps world up
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 up = cross(to_cam, right);
	float sx = length(MODEL_MATRIX[0].xyz), sy = length(MODEL_MATRIX[1].xyz);
	vec3 world = centre + right * VERTEX.x * sx + up * VERTEX.y * sy;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	fade_far = 1.0 - smoothstep(700.0, 1100.0, distance(CAMERA_POSITION_WORLD, centre));
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.y /= flatness;
	vec2 drift = vec2(TIME * 0.004, TIME * 0.0015);
	float lobes = fbm(UV * 3.1 + seed + drift);
	float fine = fbm(UV * 9.0 + seed * 1.7 - drift * 2.0);
	// flat-ish bottom, billowing top
	float bottom = smoothstep(-0.85, -0.25, uv.y + (lobes - 0.5) * 0.35);
	float body = 1.0 - length(uv * vec2(1.0, 1.15));
	float density = body * 1.25 + (lobes - 0.5) * 1.1 + (fine - 0.5) * 0.35;
	density *= bottom;
	float alpha = smoothstep(0.02, 0.32 * softness + 0.08, density) * opacity * fade_far;
	vec3 day = vec3(0.98, 0.99, 1.0), day_shade = vec3(0.74, 0.80, 0.90);
	vec3 dusk = vec3(1.0, 0.82, 0.74), dusk_shade = vec3(0.68, 0.52, 0.66);
	vec3 night = vec3(0.50, 0.56, 0.78), night_shade = vec3(0.20, 0.23, 0.38);
	vec3 lit = day * time_weights.x + dusk * time_weights.y + night * time_weights.z;
	vec3 shade = day_shade * time_weights.x + dusk_shade * time_weights.y + night_shade * time_weights.z;
	float top = clamp(UV.y * -1.0 + 1.0, 0.0, 1.0);
	float light = clamp(0.35 + (1.0 - UV.y) * 0.55 + (lobes - 0.5) * 0.4, 0.0, 1.0);
	vec3 rim = vec3(1.0, 0.86, 0.7) * time_weights.y * smoothstep(0.1, 0.0, abs(density - 0.08)) * 0.35;
	ALBEDO = mix(shade, lit, light) + rim;
	// long thin wisps read as bright slashes on a black night sky: keep them faint after dark
	ALPHA = alpha * (1.0 - 0.6 * time_weights.z * (1.0 - smoothstep(0.25, 0.4, flatness)));
}
