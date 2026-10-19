#if DEBUG
import AppKit
import HaloCore
import SwiftUI

@MainActor
enum RenderChecks {
    static func run() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/halo-visual-check", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = LRCParser().parse("[00:01.00] A moment in motion\n[00:04.00] Let the light move with you\n[00:08.00] Everything comes alive\n[00:12.00] Another horizon")
        let palette: [Color] = [.init(hex: "#4CBFFF"), .init(hex: "#F74D85"), .init(hex: "#F7D879")]
        let settings = VisualSettings()
        var results: [String] = []
        for (name, size, position, energy, beat) in [
            ("desktop-rest", CGSize(width: 1440, height: 900), 5.0, 0.15, 0.0),
            ("desktop-beat", CGSize(width: 1440, height: 900), 5.0, 0.85, 1.0),
            ("compact", CGSize(width: 1024, height: 640), 9.0, 0.6, 0.3)
        ] {
            let content = ZStack {
                Color(white: 0.065)
                LightField(settings: settings, colors: palette, energy: energy, bass: energy * 0.8, beat: beat, phase: 1.4, burst: beat)
                EditorialLyricsView(timeline: fixture, position: position, energy: energy, beat: beat, phase: 1.4,
                                    settings: settings, colors: palette)
                    .frame(width: size.width * 0.82, height: min(520, size.height * 0.76))
            }.frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            results.append("\(name): \(cgImage.width)x\(cgImage.height), \(png.count) bytes")
        }
        let icon = AppIcon.image
        guard icon.isValid, icon.representations.count > 0 else { throw CocoaError(.fileReadCorruptFile) }
        results.append("App icon decoded: \(icon.representations.count) representations")
        try results.joined(separator: "\n").write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
