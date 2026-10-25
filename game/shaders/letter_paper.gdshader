shader_type canvas_item;
// Letter paper: warm off-white with soft fibres, a centre fold, darker aged edges and a
// slightly ragged border. Everything is procedural, no textures.
uniform vec4 paper : source_color = vec4(.965, .93, .85, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float fibres = noise(uv * vec2(70.0, 45.0)) * .5 + noise(uv * vec2(340.0, 9.0)) * .5;
	vec3 c = paper.rgb * (.93 + .09 * fibres);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	c *= mix(.8, 1.0, smoothstep(0.0, .14, edge));
	float fold = 1.0 - smoothstep(0.0, .005, abs(uv.y - .5));
	c *= 1.0 - .05 * fold;
	float ragged = noise(uv * 90.0) * .011;
	COLOR = vec4(c, smoothstep(0.0, .006, edge - ragged));
}
