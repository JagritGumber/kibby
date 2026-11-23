import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: root

    property var runtime
    property string packageRoot: ""
    property string settingsPath: ""
    property var settings: ({
        enabled: true,
        intensity: 1.0,
        showErrors: true,
        // The bars along the bottom edge while Wispr listens: on/off, how
        // many across the width (0 = the look's own: 192 for Kurve, 150 for
        // Caelestia), and their height at full voice as a share of the
        // screen height. The look itself is switched with wispr-glow-style.
        // KIBBY_WISPR_BARS, KIBBY_WISPR_BAR_COUNT and KIBBY_WISPR_BAR_MAX_HEIGHT
        // in ~/.config/kibby/settings.env.
        barsEnabled: {{KIBBY_WISPR_BARS}},
        barCount: {{KIBBY_WISPR_BAR_COUNT}},
        barMaxHeight: {{KIBBY_WISPR_BAR_MAX_HEIGHT}}
    })

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: glowWindow
            required property var modelData

            screen: modelData
            visible: root.settings.enabled && root.runtime
                && (root.runtime.speechState !== "idle" || root.runtime.audioLevel > 0.015)
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            mask: Region {}
            WlrLayershell.namespace: "quickshell:kibby-edge-aura"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // The glow, drawn on the GPU: edgeglow.frag paints the four edge
            // gradients and ribbon.vert/.frag the voice ribbons as geometry,
            // segment by segment, exactly as the Canvas used to on the CPU,
            // where a full-screen repaint every frame cost more than a whole
            // core while showing. The audio ribbon the Canvas could add is left
            // out: nothing in this host publishes audio.activity, so it never
            // drew. (Shaders compile to .qsb with qsb; see each file's header.)
            Item {
                id: canvas
                anchors.fill: parent
                property real elapsed: 0
                property real smoothSpeechLevel: 0
                property real smoothAudioLevel: 0
                property var smoothSpeechSpectrum: []
                property var smoothAudioSpectrum: []

                readonly property bool speechActive: !!root.runtime && root.runtime.speechState !== "idle"
                readonly property real intensity: Number(root.settings.intensity || 1)
                // A quiet baseline and a steep rise, so each word visibly
                // swells the glow and the pauses between words settle it.
                readonly property real speechEnergy: speechActive
                    ? (0.45 + smoothSpeechLevel * 1.05) * intensity : 0
                readonly property real glowEnergy: Math.max(Math.max(0, smoothAudioLevel) * intensity * 0.42,
                    speechEnergy)
                readonly property real failed: !!root.runtime && (root.runtime.speechState === "error"
                    || root.runtime.speechState === "cancelled") ? 1 : 0
                readonly property color primary: root.runtime ? root.runtime.primary : "transparent"
                readonly property color secondary: root.runtime ? root.runtime.secondary : "transparent"
                readonly property color tertiary: root.runtime ? root.runtime.tertiary : "transparent"
                readonly property color errorColour: root.runtime ? root.runtime.error : "transparent"
                readonly property vector4d bandsLow: Qt.vector4d(band(0), band(1), band(2), band(3))
                readonly property vector4d bandsHigh: Qt.vector4d(band(4), band(5), band(6), band(7))
                // Segments around the screen's rounded rectangle, as the Canvas
                // counted them.
                readonly property real segments: {
                    const radius = Math.max(12, Math.min(28, Math.min(width, height) * 0.022));
                    const perimeter = 2 * Math.max(1, width - 2 - 2 * radius)
                        + 2 * Math.max(1, height - 2 - 2 * radius) + 2 * Math.PI * radius;
                    return Math.max(140, Math.min(260, Math.round(perimeter / 24)));
                }

                ShaderEffect {
                    anchors.fill: parent
                    fragmentShader: `file://${Quickshell.shellDir}/edgeglow.frag.qsb`
                    readonly property real w: width
                    readonly property real h: height
                    readonly property real elapsed: canvas.elapsed
                    readonly property real glowEnergy: canvas.glowEnergy
                    readonly property real failed: canvas.failed
                    readonly property color primary: canvas.primary
                    readonly property color secondary: canvas.secondary
                    readonly property color tertiary: canvas.tertiary
                    readonly property color errorColour: canvas.errorColour
                }

                // The two voice ribbons, each stroked in passes from wide and
                // faint to thin and bright, in the Canvas's order.
                Repeater {
                    model: [
                        { phase: -0.82, speed: 1.18, offset: 18, reach: 6, share: 0.72, width: 22, alpha: 0.025 },
                        { phase: -0.82, speed: 1.18, offset: 18, reach: 6, share: 0.72, width: 2.4, alpha: 0.28 },
                        { phase: 0, speed: 1, offset: 4, reach: 14, share: 1, width: 30, alpha: 0.06 },
                        { phase: 0, speed: 1, offset: 4, reach: 14, share: 1, width: 13, alpha: 0.17 },
                        { phase: 0, speed: 1, offset: 4, reach: 14, share: 1, width: 4.2, alpha: 0.76 }
                    ]

                    ShaderEffect {
                        required property var modelData
                        anchors.fill: parent
                        visible: canvas.speechEnergy > 0
                        vertexShader: `file://${Quickshell.shellDir}/ribbon.vert.qsb`
                        fragmentShader: `file://${Quickshell.shellDir}/ribbon.frag.qsb`
                        mesh: GridMesh { resolution: Qt.size(4 * canvas.segments - 1, 1) }
                        readonly property real w: width
                        readonly property real h: height
                        readonly property real elapsed: canvas.elapsed
                        readonly property real energy: canvas.speechEnergy * modelData.share
                        readonly property real failed: canvas.failed
                        readonly property real phase: modelData.phase
                        readonly property real speed: modelData.speed
                        readonly property real offset: modelData.offset
                        readonly property real reach: modelData.reach
                        readonly property real passWidth: modelData.width
                        readonly property real passAlpha: modelData.alpha
                        readonly property real segments: canvas.segments
                        readonly property color primary: canvas.primary
                        readonly property color secondary: canvas.secondary
                        readonly property color tertiary: canvas.tertiary
                        readonly property color errorColour: canvas.errorColour
                        readonly property vector4d bandsLow: canvas.bandsLow
                        readonly property vector4d bandsHigh: canvas.bandsHigh
                    }
                }

                function band(index) {
                    return Number(smoothSpeechSpectrum[index]) || 0;
                }

                function smoothSpectrum(current, target, blend) {
                    const count = Math.max(current ? current.length : 0,
                        target ? target.length : 0, 12);
                    const output = new Array(count);
                    for (let index = 0; index < count; ++index) {
                        const before = Number(current && current[index] || 0);
                        const after = Number(target && target[index] || 0);
                        output[index] = before + (after - before) * blend;
                    }
                    return output;
                }

                FrameAnimation {
                    running: glowWindow.visible
                    onTriggered: {
                        const dt = Math.min(0.05, Math.max(0.001, smoothFrameTime));
                        const speechTarget = root.runtime.speechLevel;
                        const audioTarget = root.runtime.audioLevel;
                        const levelRate = (speechTarget > canvas.smoothSpeechLevel
                            || audioTarget > canvas.smoothAudioLevel) ? 26 : 18;
                        const levelBlend = 1 - Math.exp(-dt * levelRate);
                        const spectrumBlend = 1 - Math.exp(-dt * 24);
                        canvas.elapsed += dt;
                        canvas.smoothSpeechLevel += (speechTarget
                            - canvas.smoothSpeechLevel) * levelBlend;
                        canvas.smoothAudioLevel += (audioTarget
                            - canvas.smoothAudioLevel) * levelBlend;
                        canvas.smoothSpeechSpectrum = canvas.smoothSpectrum(
                            canvas.smoothSpeechSpectrum, root.runtime.speechSpectrum,
                            spectrumBlend);
                        canvas.smoothAudioSpectrum = canvas.smoothSpectrum(
                            canvas.smoothAudioSpectrum, root.runtime.audioSpectrum,
                            spectrumBlend);
                    }
                }
            }

            BottomBars {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                visible: root.settings.barsEnabled !== false
                runtime: root.runtime
                count: Math.max(0, Number(root.settings.barCount) || 0)
                maxHeight: Number(root.settings.barMaxHeight) || 0.1
                running: glowWindow.visible
            }
        }
    }
}
