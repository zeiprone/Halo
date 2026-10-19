import SwiftUI

struct AmbientLightingView: View {
    @ObservedObject var state: AppState
    @ObservedObject var motion: VisualMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        LightField(settings: state.settings, colors: state.colors,
                   energy: motion.energy, bass: motion.bass, beat: motion.beat,
                   phase: motion.phase, reducedMotion: state.settings.reducedMotion || systemReduceMotion, burst: motion.burst)
    }
}

struct LightField: View {
    let settings: VisualSettings
    let colors: [Color]
    let energy: Double
    let bass: Double
    let beat: Double
    let phase: Double
    var reducedMotion = false
    var burst = 0.0

    var body: some View {
        let reactive = settings.ambientMode == .audioReactive
        let pulse = reactive && !reducedMotion ? beat * settings.beatStrength : 0
        let explosion = reactive && !reducedMotion ? burst * settings.burstStrength : 0
        let level = reactive ? energy : 0.5
        let low = reactive ? bass : 0.25
        let width = settings.thickness * (0.72 + low * 0.42 + pulse * 0.52 + explosion * 0.85)
        let angle = reducedMotion || settings.ambientMode == .staticLight ? 0 : phase * 120
        let palette = colors + [colors.first ?? .white]
        let gradient = AngularGradient(colors: palette, center: .center, angle: .degrees(angle))
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .stroke(gradient, lineWidth: width * 1.75)
                .blur(radius: width * 0.34)
                .opacity(0.16 + level * 0.34 + pulse * 0.18)
            RoundedRectangle(cornerRadius: 26)
                .stroke(gradient, lineWidth: width * 0.62)
                .blur(radius: width * 0.16)
                .opacity(0.32 + level * 0.46)
            if settings.pattern == .ribbons && !reducedMotion && settings.ambientMode != .staticLight {
                ForEach(0..<colors.count, id: \.self) { index in
                    let start = (phase * 0.17 + Double(index) / Double(max(1, colors.count))).truncatingRemainder(dividingBy: 1)
                    let length = 0.11 + low * 0.1
                    ribbon(from: start, to: min(1, start + length), color: colors[index], width: width, pulse: pulse)
                    if start + length > 1 {
                        ribbon(from: 0, to: start + length - 1, color: colors[index], width: width, pulse: pulse)
                    }
                }
            }
            if settings.pattern == .pulse {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(gradient, lineWidth: width * (0.18 + pulse * 0.2))
                    .padding(width * (0.12 + pulse * 0.32))
                    .blur(radius: 10 + width * 0.12)
                    .opacity(0.18 + pulse * 0.6)
            }
        }
        .padding(3)
        .opacity(min(1, settings.opacity * settings.intensity))
        .saturation(settings.saturation)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .allowsHitTesting(false)
    }

    private func ribbon(from: Double, to: Double, color: Color, width: Double, pulse: Double) -> some View {
        RoundedRectangle(cornerRadius: 28)
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: width * (0.44 + pulse * 0.22), lineCap: .round))
            .blur(radius: width * 0.21)
            .opacity(0.7)
    }
}
