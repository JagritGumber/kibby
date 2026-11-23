#version 440
// One pass of one of the glow's voice ribbons, as geometry: EdgeAura's Canvas
// stroked a chain of short butt-capped segments around the screen's rounded
// rectangle, pushed inward by the voice wave and a little noise, coloured in
// 24 palette steps and blended one segment at a time. Here each segment is a
// quad on a GridMesh (four grid columns per segment: its start and end edges,
// then two collapsed columns that join it to the next without covering
// anything), drawn in the Canvas's order: palette steps ascending from where
// the palette wraps, segments in order within a step.
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 local;    // along the segment and across it, in pixels
layout(location = 1) out vec2 segment;  // its length and half width
layout(location = 2) out vec3 colour;

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

out gl_PerVertex { vec4 gl_Position; };

const float PI = 3.14159265358979;
const float INSET = 1.0;

float R, SX, SY, ARC, PER;

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

vec4 over(vec4 dst, vec3 rgb, float alpha) {
    return vec4(rgb * alpha, alpha) + dst * (1.0 - alpha);
}

// A point at arc length d around the inset rounded rectangle, clockwise from
// the top-left end of the top edge (EdgeAura's pointAt).
vec2 pointAt(float d) {
    float s = mod(d, PER);
    float right = w - INSET;
    float bottom = h - INSET;
    if (s < SX) return vec2(INSET + R + s, INSET);
    s -= SX;
    if (s < ARC) { float a = -PI / 2.0 + s / R; return vec2(right - R + cos(a) * R, INSET + R + sin(a) * R); }
    s -= ARC;
    if (s < SY) return vec2(right, INSET + R + s);
    s -= SY;
    if (s < ARC) { float a = s / R; return vec2(right - R + cos(a) * R, bottom - R + sin(a) * R); }
    s -= ARC;
    if (s < SX) return vec2(right - R - s, bottom);
    s -= SX;
    if (s < ARC) { float a = PI / 2.0 + s / R; return vec2(INSET + R + cos(a) * R, bottom - R + sin(a) * R); }
    s -= ARC;
    if (s < SY) return vec2(INSET, bottom - R - s);
    s -= SY;
    float a = PI + s / R;
    return vec2(INSET + R + cos(a) * R, INSET + R + sin(a) * R);
}

vec2 inwardPoint(float d, float displacement) {
    vec2 point = pointAt(d);
    // On a straight edge, at least 2 px from its ends, the normal is the
    // edge's own; elsewhere take it from the neighbours 2 px away, as the
    // Canvas did.
    float s = mod(d, PER);
    if (s > 2.0 && s < SX - 2.0) return point + vec2(0.0, displacement);
    if (s > SX + ARC + 2.0 && s < SX + ARC + SY - 2.0) return point + vec2(-displacement, 0.0);
    if (s > SX + SY + 2.0 * ARC + 2.0 && s < 2.0 * SX + SY + 2.0 * ARC - 2.0) return point + vec2(0.0, -displacement);
    if (s > 2.0 * SX + SY + 3.0 * ARC + 2.0 && s < 2.0 * SX + 2.0 * SY + 3.0 * ARC - 2.0) return point + vec2(displacement, 0.0);
    vec2 t = pointAt(d + 2.0) - pointAt(d - 2.0);
    vec2 n = vec2(-t.y, t.x) / max(0.001, length(t));
    if (dot(n, vec2(w, h) * 0.5 - point) < 0.0)
        n = -n;
    return point + n * displacement;
}

// The voice wave (EdgeAura's spectrumWave): the idle flow fading out as the
// eight bands' weight rises, harmonics 2-9 summed by rotating one phasor.
float spectrumWave(float theta, float time) {
    float idle = sin(theta * 5.0 - time * 2.2) * 0.25;
    vec4 lowA = clamp(bandsLow, 0.0, 1.0);
    vec4 highA = clamp(bandsHigh, 0.0, 1.0);
    float bands[8] = float[8](lowA.x, lowA.y, lowA.z, lowA.w, highA.x, highA.y, highA.z, highA.w);
    float start = 2.0 * theta - time * 2.2;
    float stepAngle = theta - time * 0.12;
    vec2 phasor = vec2(cos(start), sin(start));
    vec2 rotation = vec2(cos(stepAngle), sin(stepAngle));
    float wave = 0.0;
    float weight = 0.0;
    for (int index = 0; index < 8; ++index) {
        wave += bands[index] * phasor.y;
        weight += bands[index];
        phasor = vec2(phasor.x * rotation.x - phasor.y * rotation.y,
            phasor.x * rotation.y + phasor.y * rotation.x);
    }
    float voice = min(1.0, weight / 0.75);
    return idle * (1.0 - voice) + wave / max(1.5, weight);
}

float displacement(float s, float phase, float speed, float offset, float reach) {
    float theta = 2.0 * PI * s / PER;
    float wave = spectrumWave(theta + phase, elapsed * speed);
    float noise = sin(theta * 3.0 + elapsed * 0.9 + phase) * 0.55 + sin(theta * 7.0 + elapsed * 2.3) * 0.25;
    return offset + wave * reach + noise * 2.4;
}


// The start (end = false) or end edge of segment k, top (side -1) or bottom
// (side 1), widened by a pixel all round for the antialiased edge.
vec2 edgePoint(float k, bool end, float side, out vec2 localOut, out vec2 segmentOut, out vec3 colourOut) {
    float stepLength = PER / segments;
    float s0 = k * stepLength;
    float s1 = (k + 1.3) * stepLength;
    vec2 a = inwardPoint(s0, displacement(s0, phase, speed, offset, reach));
    vec2 b = inwardPoint(s1, displacement(s1, phase, speed, offset, reach));
    vec2 along = b - a;
    float len = max(0.001, length(along));
    vec2 u = along / len;
    vec2 n = vec2(-u.y, u.x);
    float halfWidth = passWidth * (0.8 + energy * 0.45) * 0.5;
    float t = end ? len + 1.0 : -1.0;
    float across = side * (halfWidth + 1.0);
    localOut = vec2(t, across);
    segmentOut = vec2(len, halfWidth);
    float bucket = min(23.0, floor(fract(s0 / PER + elapsed * 0.015 + phase) * 24.0));
    colourOut = paletteAt((bucket + 0.5) / 24.0);
    return a + u * t + n * across;
}

void main() {
    R = max(12.0, min(28.0, min(w, h) * 0.022));
    SX = max(1.0, w - 2.0 * INSET - 2.0 * R);
    SY = max(1.0, h - 2.0 * INSET - 2.0 * R);
    ARC = PI * R / 2.0;
    PER = 2.0 * SX + 2.0 * SY + 4.0 * ARC;
    float cols = 4.0 * segments - 1.0;
    float c = floor(qt_MultiTexCoord0.x * cols + 0.5);
    float side = qt_MultiTexCoord0.y > 0.5 ? 1.0 : -1.0;
    float group = floor(c / 4.0);
    float role = c - 4.0 * group;
    // the segment where the palette wraps to step 0 goes first
    float shift = 1.0 - fract(elapsed * 0.015 + phase);
    float wrapStart = mod(ceil(shift * segments - 0.0001), segments);
    float k = mod(group + wrapStart, segments);
    vec2 position;
    if (role < 0.5)
        position = edgePoint(k, false, side, local, segment, colour);
    else if (role < 1.5)
        position = edgePoint(k, true, side, local, segment, colour);
    else if (role < 2.5)
        position = edgePoint(k, true, -1.0, local, segment, colour);     // collapsed onto this end's top
    else if (group + 1.0 < segments)
        position = edgePoint(mod(k + 1.0, segments), false, -1.0, local, segment, colour); // onto the next start's top
    else
        position = edgePoint(k, true, -1.0, local, segment, colour);
    gl_Position = qt_Matrix * vec4(position, 0.0, 1.0);
}
