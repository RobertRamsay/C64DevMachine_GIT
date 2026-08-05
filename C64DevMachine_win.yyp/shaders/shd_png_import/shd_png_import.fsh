varying vec2 v_vTexcoord;
varying vec4 v_vColour;
uniform float u_hue;
uniform float u_sat;
uniform float u_con;
uniform float u_bri;
uniform float u_dither_amount;
uniform int u_dither_mode; // 0=None, 1=Checker, 2=Interlace, 3=Bayer
uniform int u_is_hires;    // 0=MC (2x1 double-wide pixels), 1=HiRes (1:1 square pixels)
uniform vec3 u_palette[16];
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void main() {
    // MC snaps UVs to 2x1 blocks to simulate C64 double-wide pixels.
    // HiRes samples every column individually (1:1, 320 wide) — no pairing.
    vec2 uv = v_vTexcoord;
    float px_cols = (u_is_hires == 1) ? 320.0 : 160.0;
    uv.x = floor(uv.x * px_cols) / px_cols;
    uv.y = floor(uv.y * 200.0) / 200.0;
    vec4 texColor = texture2D(gm_BaseTexture, uv);
    vec3 col = texColor.rgb;
    // Brightness & Contrast
    col = clamp(col + vec3(u_bri), 0.0, 1.0);
    col = clamp((col - vec3(0.5)) * u_con + vec3(0.5), 0.0, 1.0);
    // Hue & Saturation
    vec3 hsv = rgb2hsv(col);
    hsv.x = fract(hsv.x + u_hue);
    if (hsv.x < 0.0) hsv.x += 1.0;
    hsv.y = clamp(hsv.y * u_sat, 0.0, 1.0);
    col = hsv2rgb(hsv);
    // Dither
    if (u_dither_mode > 0) {
        float dval = 0.0;
        float px = floor(v_vTexcoord.x * px_cols);
        float py = floor(v_vTexcoord.y * 200.0);
        if (u_dither_mode == 3) {
            int bx = int(mod(px, 4.0));
            int by = int(mod(py, 4.0));
            int idx = by * 4 + bx;
            float b_val = 0.0;
            if(idx==0) b_val=0.0; else if(idx==1) b_val=8.0; else if(idx==2) b_val=2.0; else if(idx==3) b_val=10.0;
            else if(idx==4) b_val=12.0; else if(idx==5) b_val=4.0; else if(idx==6) b_val=14.0; else if(idx==7) b_val=6.0;
            else if(idx==8) b_val=3.0; else if(idx==9) b_val=11.0; else if(idx==10) b_val=1.0; else if(idx==11) b_val=9.0;
            else if(idx==12) b_val=15.0; else if(idx==13) b_val=7.0; else if(idx==14) b_val=13.0; else if(idx==15) b_val=5.0;
            dval = (b_val / 16.0 - 0.5) * (u_dither_amount * 3.0);
        } else if (u_dither_mode == 1) {
            float check = mod(px + py, 2.0);
            dval = (check == 0.0) ? u_dither_amount : -u_dither_amount;
        } else if (u_dither_mode == 2) {
            float interlace = mod(py, 2.0);
            dval = (interlace == 0.0) ? u_dither_amount : -u_dither_amount;
        }
        col = clamp(col + vec3(dval), 0.0, 1.0);
    }
    // Nearest Pepto Palette Match
    float best_d = 999999.0;
    vec3 final_col = u_palette[0];
    // RGB distance alone lets colours such as brown and yellow act as extra
    // brightness levels when the source has been desaturated. Keep the
    // target saturation in the match so SAT=0 genuinely selects greys.
    float target_sat = rgb2hsv(col).y;
    // Explicit math for the distance to avoid HLSL compiler errors
    for (int i = 0; i < 16; i++) {
        vec3 pal = u_palette[i];
        vec3 diff = col - pal;
        float pal_sat = rgb2hsv(pal).y;
        float sat_diff = target_sat - pal_sat;
        
        // Manual weighted RGB distance plus a saturation/chroma penalty.
        // The fairly strong weight is intentional: the C64 palette has large
        // grey-level gaps that coloured entries must not fill at low SAT.
        float dist = (diff.r * diff.r * 0.299) + 
                     (diff.g * diff.g * 0.587) + 
                     (diff.b * diff.b * 0.114) +
                     (sat_diff * sat_diff * 0.75);
        if (dist < best_d) {
            best_d = dist;
            final_col = pal;
        }
    }
    gl_FragColor = vec4(final_col, 1.0);
}
