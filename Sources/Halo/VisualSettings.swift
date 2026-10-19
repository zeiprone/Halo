import Foundation
import SwiftUI

enum LyricDisplayMode: String, Codable, CaseIterable, Identifiable {
    case editorial = "Editorial", focus = "Focus", fisheye = "Fisheye"
    var id: Self { self }
}

enum AmbientAnimationMode: String, Codable, CaseIterable, Identifiable {
    case audioReactive = "Audio Reactive", ambient = "Ambient", staticLight = "Static"
    var id: Self { self }
}

enum LightPattern: String, Codable, CaseIterable, Identifiable {
    case ribbons = "Ribbons", flow = "Flow", pulse = "Pulse"
    var id: Self { self }
}

struct VisualSettings: Codable {
    var lyricMode: LyricDisplayMode = .editorial
    var fontSize = 64.0
    var lyricOpacity = 0.96
    var lyricMotion = 0.8
    var lyricVerticalPosition = 0.5
    var showSurroundingLyrics = true
    var showArtwork = false
    var artworkOpacity = 0.28
    var artworkSize = 0.32
    var syncTypography = true
    var ambientMode: AmbientAnimationMode = .audioReactive
    var pattern: LightPattern = .ribbons
    var intensity = 1.15
    var thickness = 66.0
    var opacity = 0.88
    var saturation = 1.2
    var speed = 1.4
    var sensitivity = 1.6
    var beatStrength = 0.85
    var burstStrength = 1.0
    var reducedMotion = false
    var useAlbumColors = true
    var colorCount = 3
    var primaryHex = "#4CBFFF"
    var secondaryHex = "#F74D85"
    var thirdHex = "#F7D879"

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "visualSettings.v2"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "visualSettings.v2")
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x4CBFFF
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    var hex: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
