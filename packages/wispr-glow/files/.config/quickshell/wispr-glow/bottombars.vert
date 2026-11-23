#version 440
// Wispr Flow's bottom bars, placed as geometry: one quad per bar on a GridMesh
// (four grid columns per bar: its left and right edges, then two collapsed
// columns that join it to the next bar without covering anything). Each
// vertex reads its bar's height once, so pixels never do.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 local;    // x from the bar's centre, y in item pixels
layout(location = 1) out vec3 barInfo;  // half width, top, corner radius
layout(location = 2) out vec3 tint;     // the gradient colour at this x (kurve looks)

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

out gl_PerVertex { vec4 gl_Position; };

vec3 quantise(vec3 c) { return floor(c * 255.0 + 0.5) / 255.0; }

float heightOf(int index) {
    vec4 group[64] = vec4[64](b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15,
        b16, b17, b18, b19, b20, b21, b22, b23, b24, b25, b26, b27, b28, b29, b30, b31,
        b32, b33, b34, b35, b36, b37, b38, b39, b40, b41, b42, b43, b44, b45, b46, b47,
        b48, b49, b50, b51, b52, b53, b54, b55, b56, b57, b58, b59, b60, b61, b62, b63);
    vec4 four = group[index / 4];
    int lane = index - (index / 4) * 4;
    return lane == 0 ? four.x : (lane == 1 ? four.y : (lane == 2 ? four.z : four.w));
}

vec3 across(float u) {
    vec4 stops[13] = vec4[13](c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12);
    float scaled = clamp(u, 0.0, 1.0) * max(1.0, stopCount - 1.0);
    int index = max(0, int(min(floor(scaled), stopCount - 2.0)));
    return mix(quantise(stops[index].rgb), quantise(stops[min(index + 1, 12)].rgb), scaled - float(index));
}

// The bar's left (role 0) or right (role 1) edge, top (row 0) or bottom (row 1),
// widened by a pixel for the antialiased edge. Returns the position and fills
// the varyings.
vec2 corner(int bar, float role, float row, out vec2 localOut, out vec3 info) {
    float slot = w / barTotal;
    float tallest = h - 2.0;
    float level = heightOf(bar);
    float bw;
    float barHeight;
    if (kurveLook > 0.5) {
        bw = max(1.0, slot * 2.0 / 3.0);
        barHeight = max(bw * 0.75, level * tallest);
    } else {
        bw = max(1.0, slot * 0.69);
        barHeight = level * tallest < 0.5 ? 0.0 : level * tallest;
    }
    float radius = min(bw * 0.5, (barHeight + bw * 0.5) * 0.5);
    float top = h - barHeight;
    float cx = (float(bar) + 0.5) * slot;
    float x = cx + (role < 0.5 ? -1.0 : 1.0) * (bw * 0.5 + 1.0);
    float y = row < 0.5 ? top - 1.0 : h;
    if (barHeight <= 0.0) { x = cx; y = h; }    // nothing to draw: collapse the quad
    localOut = vec2(x - cx, y);
    info = vec3(bw * 0.5, top, radius);
    return vec2(x, y);
}

void main() {
    float cols = 4.0 * barTotal - 1.0;
    float c = floor(qt_MultiTexCoord0.x * cols + 0.5);
    float row = qt_MultiTexCoord0.y > 0.5 ? 1.0 : 0.0;
    int bar = int(floor(c / 4.0));
    float role = c - 4.0 * float(bar);
    vec2 position;
    if (role < 1.5) {
        position = corner(bar, role, row, local, barInfo);
    } else if (role < 2.5) {
        position = corner(bar, 1.0, 0.0, local, barInfo);      // this bar's right top
    } else {
        position = corner(min(bar + 1, int(barTotal) - 1), 0.0, 0.0, local, barInfo); // next bar's left top
    }
    tint = failedFlag > 0.5 ? quantise(errorColour.rgb) : across(position.x / w);
    gl_Position = qt_Matrix * vec4(position, 0.0, 1.0);
}
