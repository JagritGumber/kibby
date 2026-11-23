import QtQuick
import Quickshell
import Quickshell.Io

// What Wispr Flow is doing, read from its log and the keyboard, published to
// the shared bus as "speech.activity" for the edge glow: idle, arming,
// listening, locked (hands-free), processing, success, cancelled or error,
// with the microphone's level and spectrum while recording.
//
// From Kibby's wispr-flow package 0.1.8. Added here: Wispr's own error
// notifications (no audio, no mic, offline, paste failed…), which it draws
// in the hidden bottom bar, now turn the glow red and show as a desktop
// notification.
Item {
    id: root

    property var runtime
    property string packageRoot: ""
    property string settingsPath: ""
    property var settings: ({
        logPath: "~/.config/Wispr Flow/logs/main.log",
        micReadyTimeoutMs: 1600,
        // KIBBY_WISPR_INPUT_GAIN in ~/.config/kibby/settings.env.
        // 0 = automatic gain (see scaleLevels). A number (Jagrit's EPOS
        // headset used 12) applies that fixed linear gain instead.
        inputGain: {{KIBBY_WISPR_INPUT_GAIN}}
    })
    property string liveState: "idle"
    property string errorMessage: ""
    property bool rightCtrlDown: false
    property real audioLevel: 0
    property var spectrum: []
    // cava's 48 narrow bands after the auto-gain, for the bottom lines; the
    // glow reads 12 wide ones (spectrum).
    property var bands: []
    property int generation: 0
    // Automatic gain, reset for each dictation: the mic's noise floor and the
    // loudest recent level, as shares of cava's range.
    property real noiseLevel: 0.0005
    property real peakLevel: 0
    property real levelsAt: 0
    // ascii_max_range in cava-microphone.conf. 1000 rounded soft words to 2-5.
    // The two must match; Kibby's CI checks that they do.
    readonly property int cavaRange: 10000
    // The last error shown, so Wispr's repeats (it sends NoAudio up to three
    // times in a few seconds) make one notification.
    property string lastNotice: ""
    property real lastNoticeAt: 0

    // Wispr's notifications that mean dictation went wrong, in plain words.
    // Its other notifications (tips, upsells, celebrations) are ignored.
    readonly property var errorNotices: ({
        NoAudio: "Wispr heard no sound. Check your mic isn't muted, including a headset's own mute switch.",
        NoAudioDuringDictation: "Wispr heard no sound. Check your mic isn't muted, including a headset's own mute switch.",
        NoAudioDuringDictationEscalated: "Wispr still hears no sound from your mic.",
        MicAccessError: "Wispr couldn't open the microphone.",
        MicAccessTimeout: "Wispr couldn't open the microphone.",
        MicNotReadable: "Wispr couldn't open the microphone.",
        MicDeviceUnavailable: "Wispr can't find a microphone.",
        MicNotFound: "Wispr can't find a microphone.",
        MicDisconnected: "Your microphone disconnected.",
        MicrophonePermissionRevoked: "Wispr lost permission to use the microphone.",
        AudioWorkletLoadError: "Wispr's audio engine didn't start. Restart Wispr Flow.",
        NoInternet: "Wispr is offline, so it can't transcribe.",
        TranscriptionError: "Wispr couldn't transcribe that.",
        TranscriptionEmpty: "Wispr didn't catch any words.",
        PasteFailed: "Wispr couldn't type the text into this app.",
        PasteBlocked: "Wispr couldn't type the text into this app.",
        AppDictationBlocked: "Dictation is turned off for this app.",
        HelperLoadingError: "Wispr's typing helper isn't running. Restart Wispr Flow.",
        HelperNotReady: "Wispr's typing helper isn't ready yet.",
        HelperPersistentFailure: "Wispr's typing helper keeps failing. Restart Wispr Flow.",
        SignedOut: "Wispr is signed out.",
        FailedSignIn: "Wispr couldn't sign in.",
        WeeklyWordsLimitReached: "You've reached Wispr's weekly word limit.",
        DictationMaxDurationReached: "That dictation reached Wispr's length limit.",
        CommandModeServersAreBusy: "Wispr's servers are busy. Try again in a moment.",
        DatabaseCorruptionError: "Wispr's local data is damaged.",
        DatabaseGenericError: "Wispr's local data has a problem.",
        DatabaseStorageFull: "Your disk is too full for Wispr to save."
    })

    readonly property string logPath: settings.logPath.startsWith("~/")
        ? Quickshell.env("HOME") + settings.logPath.slice(1)
        : settings.logPath
    readonly property bool recording: liveState === "listening" || liveState === "locked"
    readonly property bool micSamplingActive: liveState === "arming" || recording
    readonly property bool dictationActive: liveState === "arming"
        || liveState === "listening"
        || liveState === "locked"
        || liveState === "processing"

    function publish() {
        if (!runtime)
            return;
        runtime.publish("speech.activity", {
            state: liveState,
            level: audioLevel,
            spectrum: spectrum,
            bands: bands,
            error: errorMessage
        });
    }

    function setState(nextState, message) {
        liveState = nextState;
        if (message !== undefined && message.length > 0)
            errorMessage = message;
        if (nextState === "idle") {
            audioLevel = 0;
            spectrum = [];
            bands = [];
            errorMessage = "";
        }
        publish();
    }

    function settleToIdle(delay) {
        generation += 1;
        settleTimer.targetGeneration = generation;
        settleTimer.interval = delay;
        settleTimer.restart();
    }

    // Red glow, then a notification the shell shows like any other.
    function fail(message) {
        micReadyTimeout.stop();
        setState("error", message);
        settleToIdle(2600);
        const now = Date.now();
        if (message === lastNotice && now - lastNoticeAt < 15000)
            return;
        lastNotice = message;
        lastNoticeAt = now;
        Quickshell.execDetached(["notify-send", "-a", "Wispr Flow", "-i", "wispr-flow", "Wispr Flow", message]);
    }

    // cava's levels (0-1 of its range) to the glow's 0-1 on a decibel scale:
    // 0 just above the mic's own noise, 1 at the loudest sound of the last
    // second or two. Speech spans 30-40 dB, so a linear scale left soft words
    // near 0 next to a loud one; in decibels every word moves the glow, on any
    // mic, while silence stays at 0.
    function scaleLevels(levels) {
        const fixedGain = Number(settings.inputGain) || 0;
        if (fixedGain > 0)
            return levels.map(level => Math.max(0, Math.min(1, level * fixedGain)));
        const now = Date.now();
        const seconds = levelsAt > 0 ? Math.min(0.25, (now - levelsAt) / 1000) : 0;
        levelsAt = now;
        const loudest = Math.max(...levels);
        // The noise floor drops to any quieter moment at once and creeps up
        // 3 dB a second, so the pauses between words keep it honest.
        noiseLevel = Math.max(0.0001, loudest < noiseLevel
            ? loudest : noiseLevel * Math.pow(10, 3 * seconds / 20));
        peakLevel = Math.max(loudest, peakLevel * Math.exp(-seconds / 1.5));
        // KIBBY_WISPR_GATE_DB: how far above the noise floor a sound starts
        // to move the glow. Lower it for quiet mics, raise it for noisy ones.
        const gate = noiseLevel * Math.pow(10, {{KIBBY_WISPR_GATE_DB}} / 20);
        const top = Math.max(peakLevel, gate * Math.pow(10, 24 / 20));
        const span = Math.log(top / gate);
        return levels.map(level => level <= gate ? 0 : Math.min(1, Math.log(level / gate) / span));
    }

    function consumeLogLine(line) {
        // A key press alone is never evidence that Wispr started recording.
        const notice = line.match(/Sending notification ([A-Za-z]+)/);
        if (notice && errorNotices[notice[1]]) {
            fail(errorNotices[notice[1]]);
        } else if (line.includes("AudioStart IPC startListening")) {
            generation += 1;
            // Each dictation finds its own levels.
            noiseLevel = 0.0005;
            peakLevel = 0;
            levelsAt = 0;
            setState("arming", "");
            micReadyTimeout.restart();
        } else if (line.includes("mic ready event: false")) {
            fail("Wispr couldn't open the microphone.");
        } else if (line.includes("mic ready event: true") && line.includes("indicatorState: active")) {
            micReadyTimeout.stop();
            setState(rightCtrlDown ? "listening" : "locked", "");
        } else if (dictationActive
            && (line.includes("status=cancelled") || line.includes("updateDictationStatus: dismissed"))) {
            micReadyTimeout.stop();
            setState("cancelled", "");
            settleToIdle(420);
        } else if (line.includes("updateDictationStatus: processing")) {
            micReadyTimeout.stop();
            setState("processing", "");
        } else if (line.includes("Returned to idle") || line.includes("updateDictationStatus: idle")) {
            micReadyTimeout.stop();
            if (liveState === "processing") {
                setState("success", "");
                settleToIdle(420);
            } else if (liveState !== "error") {
                // An error keeps its red until its own settle timer ends.
                setState("idle", "");
            }
        }
    }

    function consumeInputEvent(data) {
        let event;
        try {
            event = JSON.parse(data);
        } catch (error) {
            return;
        }
        if (event.key === "right_ctrl") {
            rightCtrlDown = event.state === "down";
            if (event.state === "up" && liveState === "listening")
                lockDecisionTimer.restart();
        } else if (event.key === "escape" && event.state === "down" && dictationActive) {
            // Wispr's file log can be buffered for several seconds. The physical
            // cancel key is authoritative and gives the UI immediate feedback.
            micReadyTimeout.stop();
            lockDecisionTimer.stop();
            setState("cancelled", "");
            settleToIdle(420);
        }
    }

    Process {
        running: true
        command: ["tail", "-n", "0", "-F", root.logPath]
        stdout: SplitParser { onRead: data => root.consumeLogLine(data) }
    }

    Process {
        running: true
        command: ["python3", root.packageRoot + "/input-events.py"]
        stdout: SplitParser { onRead: data => root.consumeInputEvent(data) }
    }

    Process {
        // Start the visualizer while Wispr is opening the microphone instead of
        // cold-starting it after the delayed "mic ready" log line arrives.
        running: root.micSamplingActive
        command: ["bash", root.packageRoot + "/microphone-level.sh", root.packageRoot + "/cava-microphone.conf"]
        stdout: SplitParser {
            onRead: data => {
                const levels = data.split(";").filter(value => value.trim().length > 0)
                    .map(value => Number(value)).filter(value => !isNaN(value))
                    .map(value => value / root.cavaRange);
                if (levels.length === 0)
                    return;
                root.bands = root.scaleLevels(levels);
                // The glow's 12 wide bands: the loudest of each group.
                const group = Math.max(1, Math.round(root.bands.length / 12));
                const spectrum = [];
                for (let start = 0; start < root.bands.length; start += group)
                    spectrum.push(Math.max(...root.bands.slice(start, start + group)));
                root.spectrum = spectrum;
                root.audioLevel = Math.max(...root.spectrum);
                root.publish();
            }
        }
    }

    Timer {
        id: lockDecisionTimer
        interval: 260
        onTriggered: {
            if (root.liveState === "listening" && !root.rightCtrlDown)
                root.setState("locked", "");
        }
    }

    Timer {
        id: micReadyTimeout
        interval: Number(root.settings.micReadyTimeoutMs || 1600)
        onTriggered: {
            if (root.liveState === "arming")
                root.fail("Wispr didn't connect to the microphone.");
        }
    }

    Timer {
        id: settleTimer
        property int targetGeneration: 0
        onTriggered: {
            if (targetGeneration === root.generation)
                root.setState("idle", "");
        }
    }

    Component.onCompleted: publish()
}
