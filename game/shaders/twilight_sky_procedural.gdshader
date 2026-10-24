shader_type sky;
render_mode disable_fog;

float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),
                   mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),
                   mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float cloud(vec3 p) {
    return noise3(p)*0.55 + noise3(p*2.1)*0.27 + noise3(p*4.3)*0.13 + noise3(p*8.1)*0.05;
}
float stars(vec2 uv, float density, float threshold) {
    vec2 g=uv*density, id=floor(g), p=fract(g)-0.5;
    float h=hash3(vec3(id,13.7));
    p -= (vec2(hash3(vec3(id,1.2)),hash3(vec3(id,7.3)))-.5)*.6;
    float s=exp(-dot(p,p)*1200.0);
    return s*step(threshold,h)*(0.5+hash3(vec3(id,9.2))*2.0);
}
void sky() {
    vec3 d=normalize(EYEDIR);
    float elevation=clamp(d.y,0.0,1.0);
    vec3 color=mix(vec3(.021,.030,.095),vec3(.008,.015,.055),pow(elevation,.42));
    color=mix(color,vec3(.17,.13,.25),1.0-smoothstep(-.96,-.50,d.y));
    float band=exp(-pow((dot(d,normalize(vec3(.42,.62,.66)))-.13)*7.0,2.0));
    float n=cloud(d*9.0+vec3(11,7,3));
    float wisps=pow(max(n-.22,0.0),1.7)*band;
    color += mix(vec3(.15,.26,.65),vec3(.58,.20,.47),noise3(d*8.0))*wisps*1.20;
    color += vec3(.30,.28,.47)*pow(max(n-.40,0.0),2.0)*band;
    vec3 galaxy_direction=normalize(vec3(.55,.38,-.78));
    vec3 galaxy_x=normalize(cross(vec3(0,1,0),galaxy_direction));
    vec3 galaxy_y=cross(galaxy_direction,galaxy_x);
    float facing=max(dot(d,galaxy_direction),.01);
    vec2 gp=vec2(dot(d,galaxy_x),dot(d,galaxy_y)*1.6)/facing;
    float radius=length(gp);
    float theta=atan(gp.y,gp.x);
    float arms=pow(.5+.5*cos(theta*2.0+log(radius+.015)*4.6),5.0)*exp(-radius*8.0);
    float dust=cloud(d*39.0+vec3(5.0));
    color += mix(vec3(.20,.29,.68),vec3(.77,.36,.59),dust)*arms*(.25+dust)*step(.45,facing)*2.3;
    color += vec3(1.0,.78,.66)*exp(-radius*48.0)*step(.45,facing)*1.8;
    vec2 uv=vec2(atan(d.z,d.x)/6.2831853+.5,asin(clamp(d.y,-1.0,1.0))/3.1415926+.5);
    float s=stars(uv,630.0,.952)+stars(uv,310.0,.974)*1.8+stars(uv,1150.0,.976)*.5;
    color += vec3(.83,.89,1.0)*s*smoothstep(-.98,-.20,d.y)*1.5;
    color += vec3(.65,.77,1.0)*stars(uv,1450.0,.94)*band*.8;
    vec3 md=normalize(vec3(-.35,.28,-.94));
    float moon=dot(d,md);
    color += vec3(1,.72,.35)*pow(max(moon,0.0),350.0)*.16;
    float disk=smoothstep(.99935,.9996,moon);
    float cut=smoothstep(.99935,.9996,dot(d,normalize(md+vec3(.018,.008,.016))));
    color += vec3(1,.83,.48)*disk*(1.0-cut)*2.4;
    COLOR=color;
}
