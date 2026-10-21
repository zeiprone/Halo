import AppKit
import HaloCore
import SwiftUI

struct NotchIslandLayout {
    let hasNotch: Bool
    let compact: CGSize
    let expanded: CGSize

    init(screen: NSScreen) {
        hasNotch = screen.safeAreaInsets.top > 0
        compact = CGSize(width: 336, height: 38)
        expanded = CGSize(width: min(480, screen.frame.width * 0.82), height: 220)
    }

    func size(expanded isExpanded: Bool) -> CGSize { isExpanded ? expanded : compact }
}

private struct DockedNotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct NotchIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: PlaybackCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Namespace private var transitionSpace
    @State private var revealExpandedContent = false

    private var expanded: Bool { state.isNotchIslandExpanded }
    private var layout: NotchIslandLayout {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        return NotchIslandLayout(screen: screen)
    }
    private var artwork: Image {
        state.albumArtwork.map(Image.init(nsImage:)) ?? Image(systemName: "music.note")
    }

    var body: some View {
        ZStack(alignment: .top) {
            if revealExpandedContent {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: layout.compact.height)
                    expandedControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                compactWings
                    // Keep the compact content centered while AppKit prepares
                    // the wider expanded panel. This prevents a horizontal jump.
                    .frame(width: layout.compact.width, height: layout.compact.height)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // AppKit animates the panel frame. Follow its current bounds so SwiftUI
        // does not jump to the final size ahead of the window animation.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            DockedNotchShape(bottomRadius: expanded ? 28 : 22)
                .fill(Color.black)
                .overlay {
                    DockedNotchShape(bottomRadius: expanded ? 28 : 22)
                        .stroke(.white.opacity(expanded ? 0.12 : 0.04), lineWidth: 1)
                }
        }
        .clipShape(DockedNotchShape(bottomRadius: expanded ? 28 : 22))
        .shadow(color: .black.opacity(expanded ? 0.35 : 0.15), radius: expanded ? 18 : 6, y: 6)
        .animation(
            reduceMotion ? nil : .timingCurve(0.2, 0.78, 0.18, 1, duration: expanded ? 0.36 : 0.32),
            value: expanded
        )
        .onAppear {
            revealExpandedContent = expanded
        }
        .onChange(of: expanded) { _, isExpanded in
            updatePresentedContent(isExpanded: isExpanded)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Halo notch player")
    }

    private func updatePresentedContent(isExpanded: Bool) {
        guard !reduceMotion else {
            revealExpandedContent = isExpanded
            return
        }

        let duration = isExpanded ? 0.36 : 0.32
        withAnimation(.timingCurve(0.2, 0.78, 0.18, 1, duration: duration)) {
            revealExpandedContent = isExpanded
        }
    }

    private var compactWings: some View {
        HStack(spacing: 10) {
            artwork
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(.white)
                .matchedGeometryEffect(id: "notchArtwork", in: transitionSpace)
                .accessibilityLabel(playback.currentTrack?.title ?? "No track")

            Spacer(minLength: 0)

            AnimatedWaveform(
                motion: state.motion,
                colors: state.colors,
                active: playback.playbackState == .playing,
                barCount: 5
            )
            .frame(width: 18, height: 28)
            .matchedGeometryEffect(id: "notchWaveform", in: transitionSpace)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
    }

    private var expandedControls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                artwork
                    .resizable()
                    .scaledToFill()
                    .frame(width: 86, height: 86)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .matchedGeometryEffect(id: "notchArtwork", in: transitionSpace)
                    .accessibilityLabel(playback.currentTrack?.title ?? "No track")

                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.currentTrack?.title ?? "Halo is ready")
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                    Text(playback.currentTrack?.artist ?? "Start Spotify or YouTube Music to play music")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                AnimatedWaveform(
                    motion: state.motion,
                    colors: state.colors,
                    active: playback.playbackState == .playing
                )
                    .frame(width: 76, height: 48)
                    .matchedGeometryEffect(id: "notchWaveform", in: transitionSpace)

                Spacer(minLength: 0)
            }

            SeekBar(playback: playback)

            HStack(spacing: 22) {
                Spacer()
                Button { playback.previousTrack() } label: {
                    Image(systemName: "backward.end.fill")
                }
                    .accessibilityLabel("Previous track")
                Button { playback.playPause() } label: {
                    Image(systemName: playback.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.black)
                        .background(.white.opacity(0.94), in: Circle())
                }
                .accessibilityLabel(playback.playbackState == .playing ? "Pause" : "Play")
                Button { playback.nextTrack() } label: {
                    Image(systemName: "forward.end.fill")
                }
                    .accessibilityLabel("Next track")
                Spacer()
                Button { state.showLyrics.toggle() } label: {
                    Image(systemName: "text.quote")
                }
                .accessibilityLabel(state.showLyrics ? "Hide lyrics overlay" : "Show lyrics overlay")
                Button {
                    openWindow(id: "studio")
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Open Halo Studio")
            }
            .buttonStyle(NotchRoundButtonStyle())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct NotchRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 36, height: 36)
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0.11), in: Circle())
            .foregroundStyle(.white)
    }
}

private struct SeekBar: View {
    @ObservedObject var playback: PlaybackCoordinator
    @State private var draggedPosition: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let duration = max(1, playback.currentTrack?.duration ?? 1)
            let position = min(duration, max(0, draggedPosition ?? playback.interpolatedPosition))
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    let fraction = position / duration
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.24))
                        Capsule()
                            .fill(.white.opacity(0.94))
                            .frame(width: proxy.size.width * fraction)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                draggedPosition = duration * min(1, max(0, value.location.x / proxy.size.width))
                            }
                            .onEnded { value in
                                let target = duration * min(1, max(0, value.location.x / proxy.size.width))
                                draggedPosition = nil
                                playback.seek(to: target)
                            }
                    )
                }
                .frame(height: 5)

                HStack {
                    Text(timeString(position))
                    Spacer()
                    Text(timeString(duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playback position")
    }

    private func timeString(_ value: TimeInterval) -> String {
        let total = Int(max(0, value.isFinite ? value : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AnimatedWaveform: View {
    @ObservedObject var motion: VisualMotion
    let colors: [Color]
    let active: Bool
    var barCount = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || !active)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate * 7
                let spacing = min(3, max(1, proxy.size.width / 18))
                let barWidth = max(1, (proxy.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
                let availableHeight = max(8, proxy.size.height - 2)
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let wave = (sin(phase + Double(index) * 0.92) + 1) / 2
                        let live = active ? max(0.16, motion.energy) : 0.06
                        let height = 6 + (availableHeight - 6) * min(1, live * 0.72 + wave * 0.58)
                        Capsule()
                            .fill(waveGradient)
                            .frame(
                                width: barWidth,
                                height: reduceMotion || !active ? min(14, availableHeight) : height
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var waveGradient: LinearGradient {
        LinearGradient(
            colors: Array(colors.prefix(3)) + [.pink, .purple],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
