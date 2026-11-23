import QtQuick
import Quickshell

// Wispr Flow's voice as bars along the bottom edge of the screen. It lives in
// the glow's click-through window, so it shows and hides with the glow and
// turns red on an error. Drawn on the GPU, updated only while a bar moves.
//
// Looks, switched live by runtime.barStyle (~/.local/bin/wispr-glow-style):
// - "kurve", "wallpaper" and "rainbow" share the shape of the Kurve Plasma
//   widget (luisbocanegra/kurve, GPL-3.0) as Jagrit set it up: rounded bars
//   two parts wide to one part gap, rising one way from the bottom edge and
//   resting as small dots there, low notes on the left, eased like its cava
//   noise reduction of 77. They differ
//   in the smooth horizontal gradient across the bars: his Kurve colour list
//   (Catppuccin accents), the wallpaper's primary, secondary and tertiary, or
//   Kurve's "Hue" colours (hue 0-360, saturation 0.8, lightness 0.7).
// - "caelestia", after Caelestia's desktop visualiser (caelestia-dots/shell,
//   GPL-3.0): bars rising from the edge with rounded tops, mirrored from the
//   centre, primary fading to inversePrimary at 70%.
// Both are drawn here from scratch; neither project's code is copied.
ShaderEffect {
    id: visualiser

    // The shared bus (shell.qml): Wispr's state, the colours, barStyle, and
    // speechBands, the voice per frequency band after the glow's auto-gain.
    property var runtime
    // Bars across the width; 0 uses the look's own count.
    property int count: 0
    // Height at full voice, as a share of the screen height.
    property real maxHeight: 0.1
    // True while the glow's window is showing.
    property bool running: false
    // Each bar's height (0-1), eased towards the voice every frame.
    property var heights: []

    readonly property bool kurve: !!runtime && runtime.barStyle !== "caelestia"
    readonly property int total: count > 0 ? count : (kurve ? 192 : 150)
    readonly property bool listening: !!runtime
        && ["arming", "listening", "locked"].includes(runtime.speechState)
    readonly property bool failed: !!runtime
        && (runtime.speechState === "error" || runtime.speechState === "cancelled")
    readonly property int half: Math.ceil(total / 2)

    height: Math.ceil((parent ? parent.height : 1080) * maxHeight) + 4
    // Drawn on the GPU as one quad per bar (bottombars.vert/.frag, compiled to
    // .qsb); the Canvas it replaces cost most of a core repainting every frame.
    vertexShader: `file://${Quickshell.shellDir}/bottombars.vert.qsb`
    fragmentShader: `file://${Quickshell.shellDir}/bottombars.frag.qsb`
    mesh: GridMesh { resolution: Qt.size(Math.max(1, 4 * visualiser.barTotal - 1), 1) }
    // Fade in as Wispr starts listening, out while it processes.
    opacity: listening || failed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    // The colours across the Kurve-shaped bars, left to right.
    function colours() {
        const style = runtime ? runtime.barStyle : "kurve";
        if (style === "wallpaper")
            return [runtime.primary, runtime.secondary, runtime.tertiary];
        if (style === "rainbow") {
            const hues = [];
            for (let step = 0; step <= 12; ++step)
                hues.push(Qt.hsla(step / 12 % 1, 0.8, 0.7, 1));
            return hues;
        }
        // Jagrit's Kurve colour list.
        return ["ed8796", "a6da95", "eed49f", "8aadf4", "f5bde6", "8bd5ca", "f5a97f"].map(hex => {
            const value = parseInt(hex, 16);
            return Qt.rgba((value >> 16 & 255) / 255, (value >> 8 & 255) / 255, (value & 255) / 255, 1);
        });
    }

    // The shader's inputs.
    readonly property real w: width
    readonly property real h: height
    readonly property real barTotal: Math.min(256, total)
    readonly property real kurveLook: kurve ? 1 : 0
    readonly property real failedFlag: failed ? 1 : 0
    readonly property color errorColour: runtime ? runtime.error : "transparent"
    readonly property color primary: runtime ? runtime.primary : "transparent"
    readonly property color inversePrimary: runtime ? runtime.inversePrimary : "transparent"
    readonly property var stops: colours()
    readonly property real stopCount: stops.length
    readonly property color c0: stops[Math.min(0, stops.length - 1)]
    readonly property color c1: stops[Math.min(1, stops.length - 1)]
    readonly property color c2: stops[Math.min(2, stops.length - 1)]
    readonly property color c3: stops[Math.min(3, stops.length - 1)]
    readonly property color c4: stops[Math.min(4, stops.length - 1)]
    readonly property color c5: stops[Math.min(5, stops.length - 1)]
    readonly property color c6: stops[Math.min(6, stops.length - 1)]
    readonly property color c7: stops[Math.min(7, stops.length - 1)]
    readonly property color c8: stops[Math.min(8, stops.length - 1)]
    readonly property color c9: stops[Math.min(9, stops.length - 1)]
    readonly property color c10: stops[Math.min(10, stops.length - 1)]
    readonly property color c11: stops[Math.min(11, stops.length - 1)]
    readonly property color c12: stops[Math.min(12, stops.length - 1)]
    // The bars' heights, four to a vector (up to 256 bars).
    property vector4d b0: Qt.vector4d(0, 0, 0, 0)
    property vector4d b1: Qt.vector4d(0, 0, 0, 0)
    property vector4d b2: Qt.vector4d(0, 0, 0, 0)
    property vector4d b3: Qt.vector4d(0, 0, 0, 0)
    property vector4d b4: Qt.vector4d(0, 0, 0, 0)
    property vector4d b5: Qt.vector4d(0, 0, 0, 0)
    property vector4d b6: Qt.vector4d(0, 0, 0, 0)
    property vector4d b7: Qt.vector4d(0, 0, 0, 0)
    property vector4d b8: Qt.vector4d(0, 0, 0, 0)
    property vector4d b9: Qt.vector4d(0, 0, 0, 0)
    property vector4d b10: Qt.vector4d(0, 0, 0, 0)
    property vector4d b11: Qt.vector4d(0, 0, 0, 0)
    property vector4d b12: Qt.vector4d(0, 0, 0, 0)
    property vector4d b13: Qt.vector4d(0, 0, 0, 0)
    property vector4d b14: Qt.vector4d(0, 0, 0, 0)
    property vector4d b15: Qt.vector4d(0, 0, 0, 0)
    property vector4d b16: Qt.vector4d(0, 0, 0, 0)
    property vector4d b17: Qt.vector4d(0, 0, 0, 0)
    property vector4d b18: Qt.vector4d(0, 0, 0, 0)
    property vector4d b19: Qt.vector4d(0, 0, 0, 0)
    property vector4d b20: Qt.vector4d(0, 0, 0, 0)
    property vector4d b21: Qt.vector4d(0, 0, 0, 0)
    property vector4d b22: Qt.vector4d(0, 0, 0, 0)
    property vector4d b23: Qt.vector4d(0, 0, 0, 0)
    property vector4d b24: Qt.vector4d(0, 0, 0, 0)
    property vector4d b25: Qt.vector4d(0, 0, 0, 0)
    property vector4d b26: Qt.vector4d(0, 0, 0, 0)
    property vector4d b27: Qt.vector4d(0, 0, 0, 0)
    property vector4d b28: Qt.vector4d(0, 0, 0, 0)
    property vector4d b29: Qt.vector4d(0, 0, 0, 0)
    property vector4d b30: Qt.vector4d(0, 0, 0, 0)
    property vector4d b31: Qt.vector4d(0, 0, 0, 0)
    property vector4d b32: Qt.vector4d(0, 0, 0, 0)
    property vector4d b33: Qt.vector4d(0, 0, 0, 0)
    property vector4d b34: Qt.vector4d(0, 0, 0, 0)
    property vector4d b35: Qt.vector4d(0, 0, 0, 0)
    property vector4d b36: Qt.vector4d(0, 0, 0, 0)
    property vector4d b37: Qt.vector4d(0, 0, 0, 0)
    property vector4d b38: Qt.vector4d(0, 0, 0, 0)
    property vector4d b39: Qt.vector4d(0, 0, 0, 0)
    property vector4d b40: Qt.vector4d(0, 0, 0, 0)
    property vector4d b41: Qt.vector4d(0, 0, 0, 0)
    property vector4d b42: Qt.vector4d(0, 0, 0, 0)
    property vector4d b43: Qt.vector4d(0, 0, 0, 0)
    property vector4d b44: Qt.vector4d(0, 0, 0, 0)
    property vector4d b45: Qt.vector4d(0, 0, 0, 0)
    property vector4d b46: Qt.vector4d(0, 0, 0, 0)
    property vector4d b47: Qt.vector4d(0, 0, 0, 0)
    property vector4d b48: Qt.vector4d(0, 0, 0, 0)
    property vector4d b49: Qt.vector4d(0, 0, 0, 0)
    property vector4d b50: Qt.vector4d(0, 0, 0, 0)
    property vector4d b51: Qt.vector4d(0, 0, 0, 0)
    property vector4d b52: Qt.vector4d(0, 0, 0, 0)
    property vector4d b53: Qt.vector4d(0, 0, 0, 0)
    property vector4d b54: Qt.vector4d(0, 0, 0, 0)
    property vector4d b55: Qt.vector4d(0, 0, 0, 0)
    property vector4d b56: Qt.vector4d(0, 0, 0, 0)
    property vector4d b57: Qt.vector4d(0, 0, 0, 0)
    property vector4d b58: Qt.vector4d(0, 0, 0, 0)
    property vector4d b59: Qt.vector4d(0, 0, 0, 0)
    property vector4d b60: Qt.vector4d(0, 0, 0, 0)
    property vector4d b61: Qt.vector4d(0, 0, 0, 0)
    property vector4d b62: Qt.vector4d(0, 0, 0, 0)
    property vector4d b63: Qt.vector4d(0, 0, 0, 0)

    // Takes the eased heights and hands them to the shader.
    function applyHeights(next) {
        heights = next;
        for (let group = 0; group < 64; ++group) {
            const at = group * 4;
            if (at >= next.length)
                break;
            visualiser["b" + group] = Qt.vector4d(next[at] || 0, next[at + 1] || 0, next[at + 2] || 0, next[at + 3] || 0);
        }
    }

    FrameAnimation {
        running: visualiser.running && visualiser.visible
        onTriggered: {
            const dt = Math.min(0.05, Math.max(0.001, frameTime));
            const bands = visualiser.runtime ? visualiser.runtime.speechBands : [];
            const count = visualiser.total;
            const kurve = visualiser.kurve;
            const half = visualiser.half;
            const current = visualiser.heights;
            const voiced = visualiser.listening && !!bands && bands.length > 0;
            const last = voiced ? bands.length - 1 : 0;
            // The lowest sixth of the bands (below about 120 Hz) is hum and
            // rumble, never a voice, so it is skipped.
            const first = voiced ? Math.floor(bands.length / 6) : 0;
            // Caelestia: quick to rise, falling back over a third of its 400 ms
            // animation. Kurve: slower both ways, like its cava smoothing.
            const rise = 1 - Math.exp(-dt / (kurve ? 0.07 : 0.033));
            const fall = 1 - Math.exp(-dt / (kurve ? 0.22 : 0.133));
            const next = new Array(count);
            let moving = current.length !== count;
            for (let index = 0; index < count; ++index) {
                let goal = 0;
                if (voiced) {
                    // Where the bar reads the bands, 0 (lowest voice note) to
                    // 1 (highest): left to right for Kurve, from the centre
                    // outwards for Caelestia; interpolated, so the bar count
                    // needn't match the bands.
                    const along = kurve ? index / Math.max(1, count - 1)
                        : (index < half ? half - 1 - index : index - half) / Math.max(1, half - 1);
                    const position = first + along * (last - first);
                    const low = Math.floor(position);
                    const high = Math.min(last, low + 1);
                    const mix = position - low;
                    const level = (Number(bands[low]) || 0) * (1 - mix) + (Number(bands[high]) || 0) * mix;
                    // Lift soft and normal words (most bands sit well below
                    // the loudest); the gate keeps pauses at 0.
                    goal = level > 0 ? Math.pow(level, 0.6) : 0;
                }
                const was = current[index] || 0;
                const value = was + (goal - was) * (goal > was ? rise : fall);
                next[index] = value;
                moving = moving || Math.abs(value - was) > 0.002;
            }
            if (moving)
                visualiser.applyHeights(next);
        }
    }

}
