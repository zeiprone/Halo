import AppKit
import SwiftUI

struct ArtworkOverlayView: View {
    let image: NSImage?
    let settings: VisualSettings

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        ZStack {
                            Color.black.opacity(0.38 + (1 - settings.artworkOpacity) * 0.18)
                            LinearGradient(
                                colors: [.black.opacity(0.30), .clear, .black.opacity(0.42)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

struct ArtworkDismissControl: View {
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Label("Exit cover", systemImage: "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.72))
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Exit full-screen cover")
        .help("Exit full-screen cover")
    }
}
