shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
varying vec3 point;
uniform float night_amount = 1.0;
void vertex() {
	VERTEX *= length(MODEL_MATRIX[0].xyz);
    MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
    point=MODEL_MATRIX[3].xyz;
}
void fragment() {
    vec2 p=(UV-.5)*2.0;
    float dot_star=exp(-dot(p,p)*15.0);
    float rays=pow(max(0.0,1.0-abs(p.x)),18.0)*pow(max(0.0,1.0-abs(p.y)),2.0)+pow(max(0.0,1.0-abs(p.y)),18.0)*pow(max(0.0,1.0-abs(p.x)),2.0);
    float twinkle=.8+.2*sin(TIME*.8+point.x*13.0+point.y);
    ALBEDO=COLOR.rgb*2.2;
    ALPHA=(dot_star+rays*.32)*twinkle*night_amount;
}
