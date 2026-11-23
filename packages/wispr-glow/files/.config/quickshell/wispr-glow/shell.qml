//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

import QtQuick
import Quickshell
import Quickshell.Io

// Wispr Flow's glow. While you dictate, the screen edges glow in the
// wallpaper's colours and ripple with your voice; on an error they turn red
// and the error shows as a notification. Wispr's own bottom bar stays hidden
// (~/.local/bin/wispr-flow, and the wispr-flow rule in ~/.config/hypr/kibby/wispr-glow.lua).
//
// Rebuilt 2026-11-23 from Jagrit's Kibby packages (the wispr-glow 0.1.3
// bundle: edge-aura 0.1.2 + wispr-flow 0.1.8). They used to run inside the
// `kibby runtime` host, which stopped starting on 2026-10-12 when that tool
// was replaced. Started at login by ~/.config/hypr/kibby/wispr-glow.lua:
//     qs -n -d -p ~/.config/quickshell/wispr-glow
ShellRoot {
    // What the parts share, the same shape as Kibby's runtime bus: Wispr's
    // state, the mic level and spectrum, and the colours.
    QtObject {
        id: bus

        property string speechState: "idle"
        property real speechLevel: 0
        property var speechSpectrum: []
        property string speechError: ""
        // Nothing publishes "audio.activity" here; the glow treats it as quiet.
        property real audioLevel: 0
        property var audioSpectrum: []
        // Caelestia's scheme for the current wallpaper, followed live.
        property var scheme: ({})
        readonly property color primary: scheme.primary ? `#${scheme.primary}` : "#a4cce4"
        readonly property color secondary: scheme.secondary ? `#${scheme.secondary}` : "#b5c9d7"
        readonly property color tertiary: scheme.tertiary ? `#${scheme.tertiary}` : "#d8deff"
        readonly property color error: scheme.error ? `#${scheme.error}` : "#fa746f"

        function publish(channel, payload) {
            if (channel === "speech.activity") {
                speechState = payload.state || "idle";
                speechLevel = Number(payload.level || 0);
                speechSpectrum = payload.spectrum || [];
                speechError = payload.error || "";
            } else if (channel === "audio.activity") {
                audioLevel = Number(payload.level || 0);
                audioSpectrum = payload.spectrum || [];
            }
        }
    }

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/caelestia/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                bus.scheme = data.colours ?? data;
            } catch (error) {
                console.warn("wispr-glow: could not read the Caelestia scheme:", error);
            }
        }
    }

    WisprActivity {
        runtime: bus
        packageRoot: Quickshell.shellDir
    }

    EdgeAura {
        runtime: bus
    }
}
