shader_type spatial;
render_mode cull_back;
void vertex() {
    float seed=INSTANCE_CUSTOM.g;
    float t=fract(INSTANCE_CUSTOM.r+TIME*.63*(.88+seed*.24));
    float a=INSTANCE_CUSTOM.b*6.2831853;
    float r=.70+1.48*t;
    float y=2.22+3.05*t-4.90*t*t;
    vec3 tangent=normalize(vec3(cos(a)*1.48,3.05-9.80*t,-sin(a)*1.48));
    vec3 x=normalize(cross(tangent,vec3(0,0,-1)));
    vec3 z=cross(x,tangent);
    VERTEX=mat3(x,tangent,z)*(VERTEX*vec3(.42+seed*.42,1.0+seed,.42+seed*.42));
    VERTEX+=vec3(cos(a)*r+sin(t*63.0+seed*99.0)*.055*t*t,y,-sin(a)*r);
}
void fragment() {
    ALBEDO=vec3(.39,.73,.92);
    EMISSION=vec3(.10,.21,.30);
    ROUGHNESS=.11;
    METALLIC=.10;
    SPECULAR=.7;
}
