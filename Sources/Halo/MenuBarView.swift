import HaloCore
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlaybackMenuContent(playback: state.playback)
            toggles
            Divider()
            Button {
                openWindow(id: "studio")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Studio", systemImage: "rectangle.on.rectangle")
            }
            Button {
                state.toggleNotchIsland()
            } label: {
                Label(state.showNotchIsland ? "Hide notch player" : "Show notch player", systemImage: "capsule.fill")
            }
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Halo", systemImage: "power")
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading) {
            Toggle("Lyrics overlay", isOn: $state.showLyrics)
            Toggle("Dynamic lights", isOn: $state.showAmbient)
            Toggle("Full-screen cover", isOn: $state.settings.showArtwork)
        }
    }
}

private struct PlaybackMenuContent: View {
    @ObservedObject var playback: PlaybackCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playback.currentTrack?.title ?? "Waiting for Spotify")
                .font(.headline)
                .lineLimit(2)
            Text(playback.currentTrack?.artist ?? playback.observation.statusMessage ?? "Start a track in Spotify.")
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let error = playback.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        controls
    }

    private var controls: some View {
        HStack {
            Button { playback.previousTrack() } label: { Image(systemName: "backward.fill") }
                .help("Previous track")
            Button { playback.playPause() } label: {
                Image(systemName: playback.playbackState == .playing ? "pause.fill" : "play.fill")
            }
            .help("Play or pause")
            Button { playback.nextTrack() } label: { Image(systemName: "forward.fill") }
                .help("Next track")
            Spacer()
            Text(formatTime(playback.interpolatedPosition))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let safe = max(0, Int(time))
        return "\(safe / 60):\(String(format: "%02d", safe % 60))"
    }
}
