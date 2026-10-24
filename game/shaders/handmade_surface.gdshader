shader_type spatial;
uniform int kind = 0;
varying vec3 point;
float grain(vec3 p) {
    return sin(p.x+sin(p.z*.73)*1.4)*sin(p.y*.81+p.z*.47);
}
void vertex(){point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
    float coarse=grain(point*2.8);
    float fine=grain(point*(kind==1 ? vec3(38.0,1.8,5.0) : vec3(32.0)));
    float amount=kind==2 ? .09 : .055;
    ALBEDO=COLOR.rgb*(1.0+coarse*amount+fine*.025);
    ROUGHNESS=kind==3 ? .68 : .86;
    NORMAL=normalize(NORMAL+vec3(fine*.025,coarse*.018,fine*.015));
}
