shader_type spatial;
render_mode cull_disabled;
uniform vec3 player_position;
uniform bool leaves = true;
varying vec3 world_point;
void vertex() {
    if (leaves) VERTEX.x += sin(TIME*.65+VERTEX.y*1.7+VERTEX.z)*.018;
    world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    // Fade only the narrow corridor between the camera and the player.
    vec3 view_line=CAMERA_POSITION_WORLD-player_position;
    float len2=max(dot(view_line,view_line),.01);
    float t=dot(world_point-player_position,view_line)/len2;
    float dist=length(world_point-(player_position+view_line*clamp(t,0.0,1.0)));
    float fade=(1.0-smoothstep(.75,1.45,dist))*smoothstep(.01,.12,t)*(1.0-smoothstep(.93,1.04,t));
    float dither=fract(dot(floor(FRAGCOORD.xy),vec2(.75487766,.56984029)));
    if (dither<fade*.96) discard;
    float veins=sin(world_point.x*43.0+sin(world_point.z*18.0))*sin(world_point.y*36.0);
    float bark=sin(world_point.x*26.0+sin(world_point.y*.6)*2.0+world_point.z*13.0);
    vec3 leaf_color=mix(COLOR.rgb,vec3(dot(COLOR.rgb,vec3(.26,.55,.19))),.12);
    ALBEDO=(leaves ? leaf_color : COLOR.rgb)*(1.0+veins*.035+(leaves ? 0.0 : bark*.07));
    if (!leaves) {
        float flowing=sin(world_point.x*19.0+sin(world_point.y*1.4)*1.6+world_point.z*11.0);
        float fine=sin(world_point.x*94.0+world_point.z*62.0+sin(world_point.y*4.0)*3.0);
        ALBEDO*=1.0+flowing*.055+fine*.025;
        NORMAL=normalize(NORMAL+vec3(flowing*.065,0.0,fine*.035));
    }
    ROUGHNESS=.86;
    BACKLIGHT=leaves ? COLOR.rgb*.18 : vec3(0.0);
}
