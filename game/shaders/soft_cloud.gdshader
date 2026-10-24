shader_type spatial;
render_mode cull_back;
varying vec3 cloud_position;
uniform vec3 time_weights = vec3(0.0,0.0,1.0);
void vertex() {
    cloud_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    VERTEX.x += sin(TIME*.045+VERTEX.z*.09)*.25;
}
void fragment() {
    float variation=.5+.5*sin(cloud_position.x*.13+sin(cloud_position.z*.11));
    float detail=sin(cloud_position.x*.7+sin(cloud_position.z*.5))*sin(cloud_position.y*.9+cloud_position.z*.4);
    NORMAL=normalize(NORMAL+vec3(detail*.025,0.0,detail*.025));
    vec3 tint=vec3(.88,.93,.96)*time_weights.x+vec3(.90,.68,.66)*time_weights.y+vec3(.52,.60,.78)*time_weights.z;
    float rim=pow(1.0-max(dot(NORMAL,VIEW),0.0),2.0);
    ALBEDO=tint*(.88+variation*.12);
    EMISSION=tint*(.12+rim*.10);
    ROUGHNESS=1.0;
    BACKLIGHT=vec3(.22,.17,.27);
}
