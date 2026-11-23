#version 440
// One pass of a voice ribbon: each segment's antialiased coverage, with the
// pass's alpha, blended over what is already there (see ribbon.vert).
layout(location = 0) in vec2 local;
layout(location = 1) in vec2 segment;
layout(location = 2) in vec3 colour;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float w;            // item size in pixels
    float h;
    float elapsed;      // seconds the glow has been showing
    float energy;       // this ribbon's energy
    float failed;       // 1 on an error or cancel: everything turns red
    float phase;        // the ribbon's phase, speed, offset and reach
    float speed;
    float offset;
    float reach;
    float passWidth;    // this pass's stroke width and alpha
    float passAlpha;
    float segments;     // segments around the screen
    vec4 primary;
    vec4 secondary;
    vec4 tertiary;
    vec4 errorColour;
    vec4 bandsLow;      // smoothed voice spectrum, bands 0-3
    vec4 bandsHigh;     // bands 4-7
};

void main() {
    float len = segment.x;
    float halfWidth = segment.y;
    float cover = clamp(halfWidth - abs(local.y) + 0.5, 0.0, 1.0)
        * clamp(local.x + 0.5, 0.0, 1.0) * clamp(len - local.x + 0.5, 0.0, 1.0);
    float alpha = clamp(passAlpha * min(1.4, energy), 0.0, 1.0) * cover;
    fragColor = vec4(colour * alpha, alpha) * qt_Opacity;
}
