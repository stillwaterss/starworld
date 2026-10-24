shader_type sky;
render_mode disable_fog;
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform sampler2D galaxy_detail : source_color, filter_linear, repeat_disable;
uniform vec3 time_weights = vec3(0.0,0.0,1.0);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void sky() {
    vec3 d=normalize(EYEDIR);
    vec2 uv=vec2(atan(d.z,d.x)/6.2831853+.5,.5-asin(clamp(d.y,-1.0,1.0))/3.1415926);
    vec3 color=texture(panorama,uv).rgb;
    vec3 gd=normalize(vec3(.55,.38,-.78));
    vec3 gx=normalize(cross(vec3(0,1,0),gd));
    vec3 gy=cross(gd,gx);
    float facing=max(dot(d,gd),.01);
    vec2 gp=vec2(dot(d,gx),dot(d,gy)*1.6)/facing;
    float edge=max(abs(gp.x),abs(gp.y));
    if (facing>.5 && edge<.36) {
        vec2 patch=vec2(gp.x/.72+.5,.5-gp.y/.72);
        color=mix(color,texture(galaxy_detail,patch).rgb,1.0-smoothstep(.29,.36,edge));
    }
    float elevation=pow(max(d.y,0.0),.48);
    vec3 day=mix(vec3(.46,.70,.88),vec3(.09,.34,.65),elevation);
    vec3 dusk=mix(vec3(.72,.32,.25),vec3(.17,.10,.32),elevation);
    vec3 sun_dir=normalize(vec3(-.45,.12,-.88));
    float sun=max(dot(d,sun_dir),0.0);
    day+=vec3(1.0,.77,.43)*(pow(sun,650.0)*1.3+pow(sun,18.0)*.08);
    dusk+=vec3(1.0,.52,.20)*(pow(sun,1300.0)*1.2+pow(sun,25.0)*.28);
    vec2 p=d.xz/(abs(d.y)+.25)*2.4+vec2(TIME*.002,0.0);
    float n=noise(p)*.57+noise(p*2.03)*.28+noise(p*4.1)*.15;
    float wisps=smoothstep(.45,.72,n)*(1.0-smoothstep(.10,.65,d.y))*smoothstep(-.15,.0,d.y);
    day=mix(day,vec3(.91,.91,.82),wisps*.72);
    dusk=mix(dusk,vec3(.73,.43,.48),wisps*.62);
    // Continuous cloud ocean beneath the island, with soft patches at several scales.
    vec2 sea=d.xz/(max(0.0,-d.y)+.35)*3.0+vec2(TIME*.0018,0.0);
    float billow=noise(sea)*.50+noise(sea*2.07)*.28+noise(sea*4.13)*.15+noise(sea*8.31)*.07;
    float foam=smoothstep(.23,.78,billow);
    vec3 sea_day=mix(vec3(.28,.47,.68),vec3(.85,.91,.93),foam);
    vec3 sea_dusk=mix(vec3(.24,.18,.40),vec3(.82,.52,.42),foam);
    vec3 sea_night=mix(vec3(.018,.027,.074),vec3(.12,.16,.28),foam);
    float below=1.0-smoothstep(-.18,.02,d.y);
    day=mix(day,sea_day,below);
    dusk=mix(dusk,sea_dusk,below);
    color=mix(color,sea_night,below*.9)+vec3(.003,.005,.010);
    COLOR=day*time_weights.x+dusk*time_weights.y+color*time_weights.z;
}
