import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: root

    property var runtime
    property string packageRoot: ""
    property string settingsPath: ""
    property var settings: ({ enabled: true, intensity: 1.0, showErrors: true })

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

            Canvas {
                id: canvas
                anchors.fill: parent
                // Paint each frame in step with it. Canvas.Threaded queued
                // every requestPaint() behind its slow full-screen paints, so
                // the glow fell seconds behind the voice (5 s after 10 s of
                // speech). This host is its own process, so blocking its
                // thread for a paint costs nothing else.
                renderStrategy: Canvas.Immediate
                property real elapsed: 0
                property real smoothSpeechLevel: 0
                property real smoothAudioLevel: 0
                property var smoothSpeechSpectrum: []
                property var smoothAudioSpectrum: []

                function rgba(color, alpha) {
                    return `rgba(${Math.round(color.r * 255)},${Math.round(color.g * 255)},${Math.round(color.b * 255)},${Math.max(0, Math.min(1, alpha))})`;
                }

                function paletteAt(position, failed) {
                    if (failed)
                        return root.runtime.error;
                    const colors = [root.runtime.primary, root.runtime.secondary, root.runtime.tertiary];
                    const wrapped = ((position % 1) + 1) % 1;
                    const scaled = wrapped * colors.length;
                    const index = Math.floor(scaled) % colors.length;
                    const next = (index + 1) % colors.length;
                    const fraction = scaled - Math.floor(scaled);
                    return Qt.rgba(
                        colors[index].r + (colors[next].r - colors[index].r) * fraction,
                        colors[index].g + (colors[next].g - colors[index].g) * fraction,
                        colors[index].b + (colors[next].b - colors[index].b) * fraction,
                        1
                    );
                }

                function geometry() {
                    const inset = 1;
                    const radius = Math.max(12, Math.min(28, Math.min(width, height) * 0.022));
                    const straightX = Math.max(1, width - inset * 2 - radius * 2);
                    const straightY = Math.max(1, height - inset * 2 - radius * 2);
                    const arc = Math.PI * radius / 2;
                    return { inset, radius, straightX, straightY, arc,
                        perimeter: 2 * straightX + 2 * straightY + 4 * arc };
                }

                function pointAt(distance, geo) {
                    let s = ((distance % geo.perimeter) + geo.perimeter) % geo.perimeter;
                    const i = geo.inset;
                    const r = geo.radius;
                    const right = width - i;
                    const bottom = height - i;
                    if (s < geo.straightX) return { x: i + r + s, y: i };
                    s -= geo.straightX;
                    if (s < geo.arc) {
                        const a = -Math.PI / 2 + s / r;
                        return { x: right - r + Math.cos(a) * r, y: i + r + Math.sin(a) * r };
                    }
                    s -= geo.arc;
                    if (s < geo.straightY) return { x: right, y: i + r + s };
                    s -= geo.straightY;
                    if (s < geo.arc) {
                        const a = s / r;
                        return { x: right - r + Math.cos(a) * r, y: bottom - r + Math.sin(a) * r };
                    }
                    s -= geo.arc;
                    if (s < geo.straightX) return { x: right - r - s, y: bottom };
                    s -= geo.straightX;
                    if (s < geo.arc) {
                        const a = Math.PI / 2 + s / r;
                        return { x: i + r + Math.cos(a) * r, y: bottom - r + Math.sin(a) * r };
                    }
                    s -= geo.arc;
                    if (s < geo.straightY) return { x: i, y: bottom - r - s };
                    s -= geo.straightY;
                    const a = Math.PI + s / r;
                    return { x: i + r + Math.cos(a) * r, y: i + r + Math.sin(a) * r };
                }

                function inwardPoint(distance, geo, displacement) {
                    const point = pointAt(distance, geo);
                    const before = pointAt(distance - 2, geo);
                    const after = pointAt(distance + 2, geo);
                    const tx = after.x - before.x;
                    const ty = after.y - before.y;
                    const length = Math.max(0.001, Math.sqrt(tx * tx + ty * ty));
                    let nx = -ty / length;
                    let ny = tx / length;
                    if (nx * (width / 2 - point.x) + ny * (height / 2 - point.y) < 0) {
                        nx = -nx;
                        ny = -ny;
                    }
                    return { x: point.x + nx * displacement, y: point.y + ny * displacement };
                }

                function spectrumWave(theta, spectrum, time) {
                    const idle = Math.sin(theta * 5 - time * 2.2) * 0.25;
                    if (!spectrum || spectrum.length === 0)
                        return idle;
                    let wave = 0;
                    let weight = 0;
                    const count = Math.min(8, spectrum.length);
                    for (let index = 0; index < count; ++index) {
                        const amplitude = Math.max(0, Math.min(1, Number(spectrum[index]) || 0));
                        wave += amplitude * Math.sin((2 + index) * theta - time * (2.2 + index * 0.12));
                        weight += amplitude;
                    }
                    // smoothSpectrum() pads silence to zeros, so a quiet mic never
                    // reaches the empty case above. Keep the idle flow only until
                    // the voice drives the waves; even a soft word should win.
                    const voice = Math.min(1, weight / 0.75);
                    return idle * (1 - voice) + wave / Math.max(1.5, weight);
                }

                function drawEdgeGlow(ctx, energy, failed) {
                    if (energy <= 0)
                        return;
                    const reach = 72 + energy * 24;
                    const alpha = Math.min(0.28, 0.08 + energy * 0.13);
                    const transparent = "rgba(0,0,0,0)";
                    const edges = [
                        { x0: 0, y0: 0, x1: 0, y1: reach, x: 0, y: 0, w: width, h: reach, p: 0.12 },
                        { x0: 0, y0: height, x1: 0, y1: height - reach, x: 0, y: height - reach, w: width, h: reach, p: 0.62 },
                        { x0: 0, y0: 0, x1: reach, y1: 0, x: 0, y: 0, w: reach, h: height, p: 0.87 },
                        { x0: width, y0: 0, x1: width - reach, y1: 0, x: width - reach, y: 0, w: reach, h: height, p: 0.37 }
                    ];
                    for (const edge of edges) {
                        const gradient = ctx.createLinearGradient(edge.x0, edge.y0, edge.x1, edge.y1);
                        gradient.addColorStop(0, rgba(paletteAt(edge.p + elapsed * 0.006, failed), alpha));
                        gradient.addColorStop(0.48, rgba(paletteAt(edge.p, failed), alpha * 0.32));
                        gradient.addColorStop(1, transparent);
                        ctx.fillStyle = gradient;
                        ctx.fillRect(edge.x, edge.y, edge.w, edge.h);
                    }
                }

                function drawRibbon(ctx, geo, options) {
                    // More samples than this are visually redundant at a 2-4px
                    // stroke width, but substantially delay each Canvas frame.
                    const segments = Math.max(140, Math.min(260, Math.round(geo.perimeter / 24)));
                    const step = geo.perimeter / segments;
                    const colorBuckets = 24;
                    const buckets = Array.from({ length: colorBuckets }, () => []);
                    for (let index = 0; index < segments; ++index) {
                        const s0 = index * step;
                        const s1 = (index + 1.3) * step;
                        const theta = Math.PI * 2 * s0 / geo.perimeter;
                        const nextTheta = Math.PI * 2 * s1 / geo.perimeter;
                        const wave = spectrumWave(theta + options.phase, options.spectrum,
                            elapsed * options.speed);
                        const nextWave = spectrumWave(nextTheta + options.phase, options.spectrum,
                            elapsed * options.speed);
                        const noise = Math.sin(theta * 3 + elapsed * 0.9 + options.phase) * 0.55
                            + Math.sin(theta * 7 + elapsed * 2.3) * 0.25;
                        const nextNoise = Math.sin(nextTheta * 3 + elapsed * 0.9 + options.phase) * 0.55
                            + Math.sin(nextTheta * 7 + elapsed * 2.3) * 0.25;
                        const p0 = inwardPoint(s0, geo, options.offset + wave * options.reach + noise * 2.4);
                        const p1 = inwardPoint(s1, geo, options.offset + nextWave * options.reach + nextNoise * 2.4);
                        const palettePosition = ((s0 / geo.perimeter + elapsed * 0.015
                            + options.phase) % 1 + 1) % 1;
                        const bucket = Math.min(colorBuckets - 1,
                            Math.floor(palettePosition * colorBuckets));
                        buckets[bucket].push(p0.x, p0.y, p1.x, p1.y);
                    }
                    for (const pass of options.passes) {
                        ctx.lineWidth = pass.width * (0.8 + options.energy * 0.45);
                        for (let bucket = 0; bucket < colorBuckets; ++bucket) {
                            const points = buckets[bucket];
                            if (points.length === 0)
                                continue;
                            const color = paletteAt((bucket + 0.5) / colorBuckets,
                                options.failed);
                            ctx.strokeStyle = rgba(color,
                                pass.alpha * Math.min(1.4, options.energy));
                            ctx.beginPath();
                            for (let offset = 0; offset < points.length; offset += 4) {
                                ctx.moveTo(points[offset], points[offset + 1]);
                                ctx.lineTo(points[offset + 2], points[offset + 3]);
                            }
                            ctx.stroke();
                        }
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (!root.runtime || width < 2 || height < 2)
                        return;
                    const speechActive = root.runtime.speechState !== "idle";
                    const failed = root.runtime.speechState === "error" || root.runtime.speechState === "cancelled";
                    const intensity = Number(root.settings.intensity || 1);
                    const audioEnergy = Math.max(0, smoothAudioLevel) * intensity;
                    // A quiet baseline and a steep rise, so each word visibly
                    // swells the glow and the pauses between words settle it.
                    const speechEnergy = speechActive
                        ? (0.45 + smoothSpeechLevel * 1.05) * intensity : 0;
                    drawEdgeGlow(ctx, Math.max(audioEnergy * 0.42, speechEnergy), failed);
                    const geo = geometry();
                    if (audioEnergy > 0.015) {
                        drawRibbon(ctx, geo, {
                            phase: 1.2, speed: 0.72, offset: 15, reach: 7,
                            energy: 0.22 + audioEnergy * 0.42, spectrum: smoothAudioSpectrum,
                            failed: false, passes: [{ width: 18, alpha: 0.018 }, { width: 2.2, alpha: 0.24 }]
                        });
                    }
                    if (speechActive) {
                        drawRibbon(ctx, geo, {
                            phase: -0.82, speed: 1.18, offset: 18, reach: 6,
                            energy: speechEnergy * 0.72, spectrum: smoothSpeechSpectrum,
                            failed, passes: [{ width: 22, alpha: 0.025 }, { width: 2.4, alpha: 0.28 }]
                        });
                        drawRibbon(ctx, geo, {
                            phase: 0, speed: 1, offset: 4, reach: 14,
                            energy: speechEnergy, spectrum: smoothSpeechSpectrum,
                            failed, passes: [{ width: 30, alpha: 0.06 }, { width: 13, alpha: 0.17 }, { width: 4.2, alpha: 0.76 }]
                        });
                    }
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
                        canvas.requestPaint();
                    }
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
        }
    }
}
