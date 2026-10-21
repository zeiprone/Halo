import HaloCore
import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var state: AppState
    @State private var selected = "Lyrics"
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Label("Lyrics", systemImage: "text.alignleft").tag("Lyrics")
                Label("Dynamic Lights", systemImage: "light.beacon.max").tag("Dynamic Lights")
                Label("General", systemImage: "gearshape").tag("General")
            }
            .navigationTitle("Halo")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                NowPlayingHeader(playback: state.playback)
                Divider()
                switch selected {
                case "Dynamic Lights": AmbientPane(state: state)
                case "General": GeneralPane(state: state)
                default: LyricsPane(state: state, lyrics: state.lyrics, playback: state.playback)
                }
            }
            .navigationTitle(selected)
        }
    }
}

private struct NowPlayingHeader: View {
    @ObservedObject var playback: PlaybackCoordinator
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcon.image).resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(playback.currentTrack?.title ?? "Halo").font(.headline).lineLimit(1)
                Text(playback.currentTrack?.artist ?? "Waiting for music").foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { playback.playPause() } label: {
                Image(systemName: playback.playbackState == .playing ? "pause.fill" : "play.fill")
            }.help("Play or pause")
        }.padding(18)
    }
}

private struct LyricsPane: View {
    @ObservedObject var state: AppState
    @ObservedObject var lyrics: LyricsManager
    @ObservedObject var playback: PlaybackCoordinator
    var body: some View {
        Form {
            Section {
                LyricsOverlayView(state: state, lyrics: lyrics, motion: state.motion)
                    .frame(height: 260)
                    .background(Color(white: 0.055))
                HStack {
                    Text(lyrics.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { state.retryLyrics() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Retry lyrics lookup")
                }
                if let error = playback.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("Typography") {
                Toggle("Lyrics overlay", isOn: $state.showLyrics)
                Picker("Style", selection: $state.settings.lyricMode) {
                    ForEach(LyricDisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("React to music", isOn: $state.settings.syncTypography)
                Toggle("Surrounding lines", isOn: $state.settings.showSurroundingLyrics)
                Toggle("Full-screen cover", isOn: $state.settings.showArtwork)
                if state.settings.showArtwork {
                    Text("Cover art fills every display. Use the Exit cover button at the top-right of any display to close it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $state.settings.artworkOpacity, in: 0.08...0.8) { Text("Cover brightness") }
                }
                Slider(value: $state.settings.fontSize, in: 30...110) { Text("Type size") }
                Slider(value: $state.settings.lyricMotion, in: 0...1.5) { Text("Expression") }
                Slider(value: $state.settings.lyricOpacity, in: 0.2...1) { Text("Opacity") }
                Slider(value: $state.settings.lyricVerticalPosition, in: 0...1) { Text("Vertical position") }
                Stepper(value: $state.lyricsOffset, in: -15...15, step: 0.1) {
                    Text("Timing \(state.lyricsOffset, specifier: "%.1f") s")
                }
            }
            if lyrics.timeline.kind == .plain && !lyrics.timeline.lines.isEmpty {
                Section("Untimed lyrics") {
                    Text(lyrics.timeline.lines.map(\.text).joined(separator: "\n"))
                        .textSelection(.enabled).lineSpacing(8)
                }
            }
        }.formStyle(.grouped)
    }
}

private struct AmbientPane: View {
    @ObservedObject var state: AppState

    private enum LightingFeel: Hashable {
        case calm, balanced, intense
    }

    private var feelBinding: Binding<LightingFeel> {
        Binding(
            get: {
                switch state.settings.intensity {
                case ..<0.8: .calm
                case ..<1.2: .balanced
                default: .intense
                }
            },
            set: { feel in
                switch feel {
                case .calm: state.settings.intensity = 0.6
                case .balanced: state.settings.intensity = 1.0
                case .intense: state.settings.intensity = 1.35
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                AmbientLightingView(state: state, motion: state.motion)
                    .frame(height: 170).background(Color(white: 0.055)).clipped()
                Text(state.audioStatus).font(.caption).foregroundStyle(.secondary)
                Toggle("Dynamic lights", isOn: $state.showAmbient)
                Toggle("Full-screen cover", isOn: $state.settings.showArtwork)
                if state.settings.showArtwork {
                    Text("Applies across every overlay. Use the Exit cover button at the top-right of any display to close it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Animation", selection: $state.settings.ambientMode) {
                    ForEach(AmbientAnimationMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Pattern", selection: $state.settings.pattern) {
                    ForEach(LightPattern.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Response") {
                Text("Choose the overall feel first; fine-tune only when you want a specific look.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Feel", selection: feelBinding) {
                    Text("Calm").tag(LightingFeel.calm)
                    Text("Balanced").tag(LightingFeel.balanced)
                    Text("Intense").tag(LightingFeel.intense)
                }.pickerStyle(.segmented)
                DisclosureGroup("Fine-tune response") {
                Slider(value: $state.settings.sensitivity, in: 0.4...3.5) { Text("Sensitivity") }
                Slider(value: $state.settings.beatStrength, in: 0...1.5) { Text("Beat impact") }
                Slider(value: $state.settings.burstStrength, in: 0...1.5) { Text("Drop burst") }
                Slider(value: $state.settings.speed, in: 0.2...3) { Text("Motion speed") }
                Slider(value: $state.settings.intensity, in: 0.2...1.5) { Text("Glow") }
                Slider(value: $state.settings.thickness, in: 18...140) { Text("Spread") }
                Slider(value: $state.settings.opacity, in: 0.1...1) { Text("Opacity") }
                Slider(value: $state.settings.saturation, in: 0...2) { Text("Saturation") }
                }
            }
            Section("Palette") {
                Picker("Colors", selection: $state.settings.colorCount) {
                    Text("One").tag(1)
                    Text("Two").tag(2)
                    Text("Three").tag(3)
                }.pickerStyle(.segmented)
                Toggle("Album palette", isOn: $state.settings.useAlbumColors)
                HStack {
                    ForEach(Array(state.colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 24, height: 24)
                    }
                }
                if !state.settings.useAlbumColors {
                    ColorPicker("First", selection: colorBinding(\.primaryHex), supportsOpacity: false)
                    if state.settings.colorCount > 1 {
                        ColorPicker("Second", selection: colorBinding(\.secondaryHex), supportsOpacity: false)
                    }
                    if state.settings.colorCount > 2 {
                        ColorPicker("Third", selection: colorBinding(\.thirdHex), supportsOpacity: false)
                    }
                }
            }
        }.formStyle(.grouped)
    }

    private func colorBinding(_ key: WritableKeyPath<VisualSettings, String>) -> Binding<Color> {
        Binding(get: { Color(hex: state.settings[keyPath: key]) },
                set: { state.settings[keyPath: key] = $0.hex })
    }
}

private struct GeneralPane: View {
    @ObservedObject var state: AppState
    @State private var showsResetConfirmation = false
    var body: some View {
        Form {
            Toggle("Reduce motion", isOn: $state.settings.reducedMotion)
            LabeledContent("Audio", value: state.audioStatus)
            LabeledContent("Lock screen", value: "Unavailable")
            Button("Reset appearance", role: .destructive) { showsResetConfirmation = true }
                .confirmationDialog("Reset all visual settings?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
                    Button("Reset appearance", role: .destructive) { state.settings = VisualSettings() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your lyric, lighting, and cover preferences will return to their defaults.")
                }
        }.formStyle(.grouped)
    }
}
