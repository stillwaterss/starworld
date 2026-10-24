shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform bool waterfall = false;
varying vec3 world_point;
void vertex() {
    world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    if (waterfall) {
        VERTEX.x += sin(VERTEX.y*1.4+TIME*1.3)*.018;
    }
}
void fragment() {
    float drift=waterfall ? world_point.y*3.1+TIME*4.0 : world_point.x*2.4+world_point.z*1.8-TIME*1.5;
    float ripple=pow(.5+.5*sin(drift+sin(world_point.x*4.0+world_point.z*3.0)*.6),7.0);
    float hair=pow(.5+.5*sin(world_point.x*21.0+world_point.z*17.0),10.0);
    vec3 blue=waterfall ? vec3(.19,.52,.72) : vec3(.065,.32,.49);
    vec3 foam=vec3(.63,.88,.98);
    ALBEDO=mix(blue,foam,ripple*.55+hair*.10);
    EMISSION=mix(blue,foam,ripple*.35)*.30;
    float fine=sin(world_point.x*19.0+TIME*2.7)*sin(world_point.z*23.0-TIME*2.1);
    NORMAL=normalize(NORMAL+vec3(fine*.10,0.0,sin(drift)*.08));
    ALPHA=waterfall ? .48+ripple*.28 : .73;
    ROUGHNESS=.13;
    METALLIC=.04;
    SPECULAR=.65;
}
