shader_type spatial;
// Mist layer of the cloud sea under the islands: slow fbm streams that thin out
// toward the horizon and toward the rock bottoms, tinted with the sky blend.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec3 time_weights = vec3(0.0, 0.0, 1.0);
uniform float layer_seed = 0.0;
uniform float strength = 0.75;
varying vec3 world_pos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p = p * 2.07 + vec2(3.1, 7.7); a *= 0.5; }
	return v;
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz * 0.012 + layer_seed;
	vec2 flow = vec2(TIME * 0.006, TIME * 0.0025);
	float d = fbm(p + flow) * 0.65 + fbm(p * 2.3 - flow * 1.7) * 0.35;
	float r = length(world_pos.xz) / 420.0;
	float edge = 1.0 - smoothstep(0.55, 1.0, r);
	float alpha = smoothstep(0.38, 0.72, d) * strength * edge;
	vec3 day = vec3(0.95, 0.97, 1.0), dusk = vec3(0.98, 0.78, 0.76), night = vec3(0.36, 0.42, 0.64);
	vec3 tint = day * time_weights.x + dusk * time_weights.y + night * time_weights.z;
	ALBEDO = tint * (0.86 + d * 0.2);
	ALPHA = alpha;
}
