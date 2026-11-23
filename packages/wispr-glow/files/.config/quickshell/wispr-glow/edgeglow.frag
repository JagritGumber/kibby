#version 440
// The glow's four edge gradients (EdgeAura's drawEdgeGlow): the palette at
// each edge, a third of the alpha at 48%, transparent at the far end,
// interpolated premultiplied as the Canvas did, blended top, bottom, left,
// right. The voice ribbons are drawn over it by ribbon.vert/.frag.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float w;
    float h;
    float elapsed;
    float glowEnergy;
    float failed;
    vec4 primary;
    vec4 secondary;
    vec4 tertiary;
    vec4 errorColour;
};

const float PI = 3.14159265358979;
const float INSET = 1.0;


vec3 quantise(vec3 c) { return floor(c * 255.0 + 0.5) / 255.0; }

// The palette at a position around the colour wheel, as rgba() in the
// Canvas rounded it.
vec3 paletteAt(float position) {
    if (failed > 0.5)
        return quantise(errorColour.rgb);
    float scaled = fract(position) * 3.0;
    float index = floor(scaled);
    float fraction = scaled - index;
    vec3 from = index < 0.5 ? primary.rgb : (index < 1.5 ? secondary.rgb : tertiary.rgb);
    vec3 to = index < 0.5 ? secondary.rgb : (index < 1.5 ? tertiary.rgb : primary.rgb);
    return quantise(mix(from, to, fraction));
}


vec4 edgeGradient(vec4 dst, float t, float inside, float p, float alpha) {
    if (inside <= 0.0)
        return dst;
    vec4 c0 = vec4(paletteAt(p + elapsed * 0.006) * alpha, alpha);
    vec4 c1 = vec4(paletteAt(p) * alpha * 0.32, alpha * 0.32);
    vec4 colour = t < 0.48 ? mix(c0, c1, t / 0.48) : mix(c1, vec4(0.0), clamp((t - 0.48) / 0.52, 0.0, 1.0));
    colour *= inside;
    return colour + dst * (1.0 - colour.a);
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(w, h);
    vec4 colour = vec4(0.0);
    if (glowEnergy > 0.0) {
        float reach = 72.0 + glowEnergy * 24.0;
        float alpha = min(0.28, 0.08 + glowEnergy * 0.13);
        colour = edgeGradient(colour, p.y / reach, clamp(reach - p.y + 0.5, 0.0, 1.0), 0.12, alpha);
        colour = edgeGradient(colour, (h - p.y) / reach, clamp(p.y - (h - reach) + 0.5, 0.0, 1.0), 0.62, alpha);
        colour = edgeGradient(colour, p.x / reach, clamp(reach - p.x + 0.5, 0.0, 1.0), 0.87, alpha);
        colour = edgeGradient(colour, (w - p.x) / reach, clamp(p.x - (w - reach) + 0.5, 0.0, 1.0), 0.37, alpha);
    }
    fragColor = colour * qt_Opacity;
}
