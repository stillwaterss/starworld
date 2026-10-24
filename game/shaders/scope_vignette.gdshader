shader_type canvas_item;
uniform float aspect_ratio = 1.7777778;
void fragment() {
    vec2 p=(UV-.5)*vec2(aspect_ratio,1.0);
    float radius=length(p);
    float outside=smoothstep(.418,.432,radius);
    float rim=smoothstep(.414,.419,radius)*(1.0-smoothstep(.421,.427,radius));
    COLOR=vec4(mix(vec3(.018,.026,.060),vec3(.62,.53,.36),rim),max(outside*.97,rim*.7));
}
