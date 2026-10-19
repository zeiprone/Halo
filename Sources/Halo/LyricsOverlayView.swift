import HaloCore
import SwiftUI

struct LyricsOverlayView: View {
    @ObservedObject var state: AppState
    @ObservedObject var lyrics: LyricsManager
    @ObservedObject var motion: VisualMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        if lyrics.timeline.kind == .plain, !lyrics.timeline.lines.isEmpty {
            UntimedLyricsOverlayView(timeline: lyrics.timeline, settings: state.settings)
        } else if lyrics.timeline.kind != .plain {
            EditorialLyricsView(timeline: lyrics.timeline, position: motion.position,
                                energy: motion.energy, beat: motion.beat, phase: motion.phase,
                                settings: state.settings, colors: state.colors,
                                reducedMotion: state.settings.reducedMotion || systemReduceMotion)
        } else {
            EmptyView()
        }
    }
}

struct UntimedLyricsOverlayView: View {
    let timeline: LyricsTimeline
    let settings: VisualSettings

    private var excerpt: String {
        timeline.lines.prefix(10).map(\.text).joined(separator: "\n")
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                Label("Unsynced lyrics", systemImage: "text.alignleft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(excerpt)
                    .font(.system(size: min(28, settings.fontSize * 0.42), weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(settings.lyricOpacity))
                    .lineLimit(10)
                    .multilineTextAlignment(.leading)
            }
            .padding(28)
            .frame(maxWidth: geometry.size.width * 0.84, alignment: .leading)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.72), radius: 18, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .allowsHitTesting(false)
    }
}

struct EditorialLyricsView: View {
    let timeline: LyricsTimeline
    let position: Double
    let energy: Double
    let beat: Double
    let phase: Double
    let settings: VisualSettings
    let colors: [Color]
    var reducedMotion = false

    var body: some View {
        GeometryReader { geometry in
            let active = timeline.activeLineIndex(at: position)
            let rowHeight = geometry.size.height * 0.43
            let index = active ?? -1
            ZStack {
                ForEach(visibleRelativeSlots, id: \.self) { relative in
                    let lineIndex = index + relative
                    let line = lineIndex >= 0 && lineIndex < timeline.lines.count ? timeline.lines[lineIndex] : nil
                    let isActive = relative == 0
                    let liveEnergy = settings.syncTypography && !reducedMotion ? energy : 0
                    let liveBeat = settings.syncTypography && !reducedMotion ? beat : 0
                    let editorial = settings.lyricMode == .editorial
                    let amount = settings.lyricMotion
                    let size = min(settings.fontSize, rowHeight * 0.36)
                    lyricText(line, index: lineIndex, active: isActive, size: size)
                        .multilineTextAlignment(editorial ? (lineIndex.isMultiple(of: 2) ? .leading : .trailing) : .center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.42)
                        .frame(width: geometry.size.width * 0.88, height: rowHeight)
                        .scaleEffect(isActive ? 1 + liveEnergy * 0.035 * amount + liveBeat * 0.055 * amount : 0.66)
                        .rotationEffect(.degrees(editorial && isActive ? sin(phase * 2) * liveEnergy * amount * 1.2 : 0))
                        .rotation3DEffect(.degrees(settings.lyricMode == .fisheye ? Double(relative) * -18 : 0), axis: (x: 1, y: 0, z: 0))
                        .blur(radius: isActive ? 0 : 0.6)
                        .opacity(isActive ? settings.lyricOpacity : settings.lyricOpacity * 0.23)
                        .shadow(color: .black.opacity(0.85), radius: 12, y: 3)
                        .shadow(color: isActive ? accent(lineIndex).opacity(liveBeat * 0.45) : .clear, radius: 18)
                        .offset(x: editorial ? CGFloat(relative) * 18 : 0,
                                y: CGFloat(relative) * rowHeight * 0.82 - (isActive ? liveBeat * amount * 5 : 0))
                        .contentTransition(.opacity)
                        .animation(reducedMotion ? nil : .easeInOut(duration: 0.46), value: lineIndex)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private var visibleRelativeSlots: Range<Int> {
        settings.showSurroundingLyrics ? (-1..<2) : (0..<1)
    }

    private func accent(_ index: Int) -> Color {
        guard !colors.isEmpty else { return .white }
        let normalizedIndex = ((index % colors.count) + colors.count) % colors.count
        return colors[normalizedIndex]
    }

    private func lyricText(_ line: LyricLine?, index: Int, active: Bool, size: Double) -> Text {
        guard let line, !line.text.isEmpty, index >= 0 else { return Text("") }
        let editorial = settings.lyricMode == .editorial
        let serif = editorial && !index.isMultiple(of: 2)
        let design: Font.Design = serif ? .serif : .default
        let font = Font.system(size: size, weight: serif ? .semibold : .heavy, design: design)
        if !line.words.isEmpty && active {
            return line.words.enumerated().reduce(Text("")) { result, item in
                let word = item.element
                let end = word.endTime ?? (item.offset + 1 < line.words.count ? line.words[item.offset + 1].startTime : line.endTime ?? .infinity)
                let current = position >= word.startTime && position < end
                var part = Text(word.text).font(current ? font.bold() : font)
                    .foregroundColor(current ? accent(index) : .white.opacity(position >= word.startTime ? 0.95 : 0.4))
                if serif { part = part.italic() }
                return result + part
            }
        }
        // Line-only timing drives composition, not invented word timestamps.
        let words = line.text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let emphasis = words.indices.max { words[$0].count < words[$1].count }
        return words.enumerated().reduce(Text("")) { result, item in
            let emphasized = editorial && item.offset == emphasis && active
            var part = Text(item.element + (item.offset == words.count - 1 ? "" : " "))
                .font(emphasized ? .system(size: size * 1.16, weight: .black, design: design) : font)
                .foregroundColor(emphasized ? accent(index) : .white)
            if serif { part = part.italic() }
            return result + part
        }
    }
}
