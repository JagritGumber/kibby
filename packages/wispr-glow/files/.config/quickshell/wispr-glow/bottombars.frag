#version 440
// Wispr Flow's bottom bars: the coverage and colour inside each bar's quad
// (see bottombars.vert). Rounded tops; the base runs past the bottom edge.
//   kurve looks: the horizontal gradient from the vertex shader, at 90%
//   caelestia: primary at the top to inversePrimary at the base, at 70%
layout(location = 0) in vec2 local;
layout(location = 1) in vec3 barInfo;
layout(location = 2) in vec3 tint;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float w;
    float h;
    float barTotal;     // bars across the width
    float kurveLook;    // 1 for the kurve, wallpaper and rainbow looks
    float failedFlag;   // 1 on an error or cancel
    float stopCount;    // colour stops across the width (kurve looks)
    vec4 errorColour;
    vec4 primary;
    vec4 inversePrimary;
    vec4 c0; vec4 c1; vec4 c2; vec4 c3; vec4 c4; vec4 c5; vec4 c6;
    vec4 c7; vec4 c8; vec4 c9; vec4 c10; vec4 c11; vec4 c12;
    vec4 b0; vec4 b1; vec4 b2; vec4 b3; vec4 b4; vec4 b5; vec4 b6; vec4 b7;
    vec4 b8; vec4 b9; vec4 b10; vec4 b11; vec4 b12; vec4 b13; vec4 b14; vec4 b15;
    vec4 b16; vec4 b17; vec4 b18; vec4 b19; vec4 b20; vec4 b21; vec4 b22; vec4 b23;
    vec4 b24; vec4 b25; vec4 b26; vec4 b27; vec4 b28; vec4 b29; vec4 b30; vec4 b31;
    vec4 b32; vec4 b33; vec4 b34; vec4 b35; vec4 b36; vec4 b37; vec4 b38; vec4 b39;
    vec4 b40; vec4 b41; vec4 b42; vec4 b43; vec4 b44; vec4 b45; vec4 b46; vec4 b47;
    vec4 b48; vec4 b49; vec4 b50; vec4 b51; vec4 b52; vec4 b53; vec4 b54; vec4 b55;
    vec4 b56; vec4 b57; vec4 b58; vec4 b59; vec4 b60; vec4 b61; vec4 b62; vec4 b63;
};

vec3 quantise(vec3 c) { return floor(c * 255.0 + 0.5) / 255.0; }

void main() {
    float halfWidth = barInfo.x;
    float top = barInfo.y;
    float radius = barInfo.z;
    vec2 centre = vec2(0.0, (top + h + radius) * 0.5);
    vec2 halfSize = vec2(halfWidth, (h + radius - top) * 0.5);
    vec2 q = abs(local - centre) - halfSize + radius;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float cover = clamp(0.5 - d, 0.0, 1.0);
    vec3 rgb;
    float alpha;
    if (failedFlag > 0.5 || kurveLook > 0.5) {
        rgb = tint;
        alpha = kurveLook > 0.5 ? 0.9 : 0.7;
    } else {
        float tallest = h - 2.0;
        float t = clamp((local.y - (h - tallest)) / tallest, 0.0, 1.0);
        rgb = mix(quantise(primary.rgb), quantise(inversePrimary.rgb), t);
        alpha = 0.7;
    }
    fragColor = vec4(rgb * alpha, alpha) * cover * qt_Opacity;
}
