import AppKit
import Foundation

public struct HaloPalette: Sendable, Equatable {
    public let primaryHex: String
    public let secondaryHex: String
    public let thirdHex: String

    public static let fallback = HaloPalette(primaryHex: "#7CC7FF", secondaryHex: "#FF7AC8", thirdHex: "#F7D879")
}

public enum AlbumColorExtractor {
    public static func palette(from image: NSImage?) -> HaloPalette {
        guard let image,
              let bitmap = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else {
            return .fallback
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return .fallback }

        var samples: [(CGFloat, CGFloat, CGFloat, CGFloat)] = []
        let stepX = max(1, width / 24)
        let stepY = max(1, height / 24)

        for x in stride(from: 0, to: width, by: stepX) {
            for y in stride(from: 0, to: height, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let score = color.saturationComponent * (0.35 + color.brightnessComponent)
                samples.append((color.redComponent, color.greenComponent, color.blueComponent, score))
            }
        }

        let sorted = samples.sorted { $0.3 > $1.3 }
        guard let first = sorted.first else { return .fallback }
        let second = sorted.dropFirst().first { distance($0, first) > 0.25 } ?? first
        let third = sorted.first { distance($0, first) > 0.5 && distance($0, second) > 0.4 } ?? sorted[sorted.count / 2]

        return HaloPalette(primaryHex: hex(red: first.0, green: first.1, blue: first.2), secondaryHex: hex(red: second.0, green: second.1, blue: second.2), thirdHex: hex(red: third.0, green: third.1, blue: third.2))
    }

    private static func distance(_ lhs: (CGFloat, CGFloat, CGFloat, CGFloat), _ rhs: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CGFloat {
        abs(lhs.0 - rhs.0) + abs(lhs.1 - rhs.1) + abs(lhs.2 - rhs.2)
    }

    private static func hex(red: CGFloat, green: CGFloat, blue: CGFloat) -> String {
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
