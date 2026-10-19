import HaloCore
import SwiftUI

@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.state)
                .frame(width: 320)
                .padding(12)
        } label: {
            Image(nsImage: AppIcon.menuImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)

        Window("Halo Studio", id: "studio") {
            StudioView()
                .environmentObject(appDelegate.state)
                .frame(minWidth: 780, minHeight: 540)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the menu bar extra while exposing the app in Dock and Finder.
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.image
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--render-check") {
            do { try RenderChecks.run() } catch { NSLog("Halo render check failed: %@", String(describing: error)) }
            NSApp.terminate(nil)
            return
        }
        #endif
        state.start()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-check") {
            Task { @MainActor in
                var maxEnergy = 0.0
                var maxBurst = 0.0
                for _ in 0..<40 {
                    try? await Task.sleep(for: .milliseconds(200))
                    maxEnergy = max(maxEnergy, state.motion.energy)
                    maxBurst = max(maxBurst, state.motion.burst)
                }
                let report: [String: Any] = [
                    "playback": state.playback.playbackState.rawValue,
                    "hasTrack": state.playback.currentTrack != nil,
                    "lyricsLines": state.lyrics.timeline.lines.count,
                    "lyricsStatus": state.lyrics.status,
                    "audioRunning": state.audioCapture.isRunning,
                    "audioSamplesReceived": state.audioCapture.hasRecentSamples,
                    "maxEnergy": maxEnergy,
                    "maxBurst": maxBurst
                ]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: "/private/tmp/halo-smoke-check.json"), options: .atomic)
                }
            }
        }
        #endif
        // Thirty visual updates per second keeps the reactive motion fluid while avoiding a full SwiftUI tree walk at 60 Hz.
        timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(handleTimer(_:)), userInfo: nil, repeats: true)
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    @objc private func handleTimer(_ timer: Timer) {
        state.tick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        state.stop()
    }
}

@MainActor
enum AppIcon {
    static var image: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:)) ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Halo")!
    }
    static var menuImage: NSImage {
        let icon = whiteImage
        icon.size = NSSize(width: 20, height: 20)
        icon.isTemplate = true
        return icon
    }

    static let whiteImage: NSImage = makeWhiteImage()

    private static func makeWhiteImage() -> NSImage {
        guard let source = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
              let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: source.pixelsWide, pixelsHigh: source.pixelsHigh,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        for y in 0..<source.pixelsHigh {
            for x in 0..<source.pixelsWide {
                let color = source.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let luminance = max(color?.redComponent ?? 0, max(color?.greenComponent ?? 0, color?.blueComponent ?? 0))
                let alpha = max(0, min(1, (luminance - 0.08) / 0.72))
                output.setColor(NSColor.white.withAlphaComponent(alpha), atX: x, y: y)
            }
        }
        let icon = NSImage(size: source.size)
        icon.addRepresentation(output)
        return icon
    }
}
