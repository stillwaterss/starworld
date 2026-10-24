shader_type canvas_item;
// Photo-mode overlay: soft colour wash and vignette, no screen read so every renderer works.
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform float vignette = 0.2;
void fragment() {
	vec2 p = UV - 0.5;
	float edge = smoothstep(0.32, 0.78, length(p * vec2(1.15, 1.0)));
	vec3 rgb = mix(tint.rgb, vec3(0.05, 0.04, 0.09), edge);
	COLOR = vec4(rgb, max(tint.a * (1.0 - edge), edge * vignette));
}
