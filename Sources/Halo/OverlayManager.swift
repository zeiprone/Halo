import AppKit
import SwiftUI

@MainActor
final class OverlayManager {
    private var lyricsWindow: NSPanel?
    private var notchIslandWindow: NSPanel?
    private var notchTargetFrame: NSRect?
    private var notchHoverTimer: Timer?
    private var hoverBeganAt: Date?
    private var hoverEndedAt: Date?
    private var artworkWindows: [CGDirectDisplayID: NSPanel] = [:]
    private var artworkControlWindows: [CGDirectDisplayID: NSPanel] = [:]
    private var ambientWindows: [CGDirectDisplayID: NSPanel] = [:]
    private weak var state: AppState?

    func configure(state: AppState) { self.state = state }

    func setLyricsVisible(_ visible: Bool) {
        guard let state else { return }
        if visible {
            if lyricsWindow == nil {
                let panel = makePanel()
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                panel.contentView = NSHostingView(rootView: LyricsOverlayView(state: state, lyrics: state.lyrics, motion: state.motion))
                lyricsWindow = panel
            }
            repositionLyrics()
            lyricsWindow?.orderFrontRegardless()
        } else {
            lyricsWindow?.orderOut(nil)
        }
    }

    func repositionLyrics() {
        guard let state, let panel = lyricsWindow, let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = min(1200, visible.width * 0.88)
        let height = min(520, visible.height * 0.76)
        let y = visible.minY + (visible.height - height) * (1 - state.settings.lyricVerticalPosition)
        let frame = NSRect(x: visible.midX - width / 2, y: y, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    func setAmbientVisible(_ visible: Bool) {
        if visible { refreshDisplays() }
        for panel in ambientWindows.values {
            if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
    }

    func setArtworkVisible(_ visible: Bool) {
        guard state != nil else { return }
        if visible {
            refreshDisplays()
            for panel in artworkWindows.values { panel.orderFrontRegardless() }
        } else {
            for panel in artworkWindows.values { panel.orderOut(nil) }
            for panel in artworkControlWindows.values { panel.orderOut(nil) }
        }
        updateArtwork()
    }

    func updateArtwork() {
        guard let state else { return }
        for panel in artworkWindows.values {
            guard let host = panel.contentView as? NSHostingView<ArtworkOverlayView> else { continue }
            host.rootView = ArtworkOverlayView(image: state.albumArtwork, settings: state.settings)
        }
    }

    func repositionNotchIsland() {
        guard let state, let panel = notchIslandWindow, let screen = notchScreen else { return }
        let layout = NotchIslandLayout(screen: screen)
        let size = layout.size(expanded: state.isNotchIslandExpanded)
        // The physical notch meets the display's top edge. visibleFrame.maxY
        // stops below the menu bar and caused the visible gap in the old HUD.
        let top = layout.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - 8
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
        guard notchTargetFrame != frame else { return }
        let shouldAnimate = panel.isVisible && notchTargetFrame != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        notchTargetFrame = frame
        guard shouldAnimate else {
            panel.setFrame(frame, display: true)
            return
        }

        if state.isNotchIslandExpanded {
            // Prepare the expanded width without tweening across the physical
            // notch, then reveal the island only by growing downward.
            let preparedFrame = NSRect(
                x: frame.minX,
                y: top - panel.frame.height,
                width: frame.width,
                height: panel.frame.height
            )
            panel.setFrame(preparedFrame, display: true)
            animateNotchPanel(panel, to: frame, duration: 0.36)
        } else {
            // Collapse vertically first. Once the surface is compact-height,
            // tighten its width without exposing a horizontal seam at the top.
            let collapsedWideFrame = NSRect(
                x: screen.frame.midX - panel.frame.width / 2,
                y: top - frame.height,
                width: panel.frame.width,
                height: frame.height
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = notchTimingFunction
                panel.animator().setFrame(collapsedWideFrame, display: true)
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, let panel,
                          self.notchTargetFrame == frame,
                          self.state?.isNotchIslandExpanded == false else { return }
                    panel.setFrame(frame, display: true)
                }
            }
        }
    }

    private var notchTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.78, 0.18, 1)
    }

    private func animateNotchPanel(_ panel: NSPanel, to frame: NSRect, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = notchTimingFunction
            panel.animator().setFrame(frame, display: true)
        }
    }

    func setNotchIslandVisible(_ visible: Bool) {
        if visible {
            ensureNotchIsland()
            repositionNotchIsland()
            notchIslandWindow?.orderFrontRegardless()
            startNotchHoverTracking()
        } else {
            stopNotchHoverTracking()
            notchIslandWindow?.orderOut(nil)
        }
    }

    private func ensureNotchIsland() {
        guard notchIslandWindow == nil, let state else { return }
        let panel = makePanel(interactive: true)
        panel.level = .statusBar
        panel.contentView = NSHostingView(rootView: NotchIslandView(state: state, playback: state.playback))
        notchIslandWindow = panel
    }

    private func startNotchHoverTracking() {
        guard notchHoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNotchHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        notchHoverTimer = timer
    }

    private func stopNotchHoverTracking() {
        notchHoverTimer?.invalidate()
        notchHoverTimer = nil
        hoverBeganAt = nil
        hoverEndedAt = nil
    }

    private func updateNotchHover() {
        guard let state, let panel = notchIslandWindow, panel.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        let now = Date()
        let hitFrame = state.isNotchIslandExpanded
            ? panel.frame.insetBy(dx: -8, dy: -8)
            : panel.frame
        if hitFrame.contains(pointer) {
            hoverEndedAt = nil
            if !state.isNotchIslandExpanded {
                if let began = hoverBeganAt, now.timeIntervalSince(began) >= 0.12 {
                    hoverBeganAt = nil
                    state.setNotchIslandExpanded(true)
                } else if hoverBeganAt == nil {
                    hoverBeganAt = now
                }
            }
        } else {
            hoverBeganAt = nil
            if state.isNotchIslandExpanded {
                if let ended = hoverEndedAt, now.timeIntervalSince(ended) >= 0.3 {
                    hoverEndedAt = nil
                    state.setNotchIslandExpanded(false)
                } else if hoverEndedAt == nil {
                    hoverEndedAt = now
                }
            }
        }
    }

    func refreshDisplays() {
        guard let state else { return }
        repositionLyrics()
        repositionNotchIsland()
        let screens = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { ($0.uint32Value, screen) }
        })
        for id in Array(ambientWindows.keys) where screens[id] == nil {
            ambientWindows.removeValue(forKey: id)?.close()
        }
        if state.showAmbient {
            for (id, screen) in screens {
                if let panel = ambientWindows[id] {
                    if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
                } else {
                    let panel = makePanel()
                    panel.setFrame(screen.frame, display: false)
                    panel.contentView = NSHostingView(rootView: AmbientLightingView(state: state, motion: state.motion))
                    ambientWindows[id] = panel
                    panel.orderFrontRegardless()
                }
            }
        }

        for id in Array(artworkWindows.keys) where screens[id] == nil {
            artworkWindows.removeValue(forKey: id)?.close()
        }
        for id in Array(artworkControlWindows.keys) where screens[id] == nil {
            artworkControlWindows.removeValue(forKey: id)?.close()
        }
        guard state.settings.showArtwork else {
            artworkWindows.values.forEach { $0.orderOut(nil) }
            artworkControlWindows.values.forEach { $0.orderOut(nil) }
            return
        }
        for (id, screen) in screens {
            if let panel = artworkWindows[id] {
                if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
            } else {
                let panel = makePanel()
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
                panel.setFrame(screen.frame, display: false)
                panel.contentView = NSHostingView(rootView: ArtworkOverlayView(image: state.albumArtwork, settings: state.settings))
                artworkWindows[id] = panel
                panel.orderFrontRegardless()
            }

            if let control = artworkControlWindows[id] {
                positionArtworkControl(control, on: screen)
                control.orderFrontRegardless()
            } else {
                let control = makePanel(interactive: true)
                control.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
                control.contentView = NSHostingView(rootView: ArtworkDismissControl { [weak state] in
                    state?.hideArtwork()
                })
                positionArtworkControl(control, on: screen)
                artworkControlWindows[id] = control
                control.orderFrontRegardless()
            }
        }
    }

    private func positionArtworkControl(_ panel: NSPanel, on screen: NSScreen) {
        let size = NSSize(width: 176, height: 38)
        let frame = NSRect(
            x: screen.visibleFrame.maxX - size.width - 18,
            y: screen.visibleFrame.maxY - size.height - 14,
            width: size.width,
            height: size.height
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func makePanel(interactive: Bool) -> NSPanel {
        let panel = makePanel()
        panel.ignoresMouseEvents = !interactive
        return panel
    }

    private var notchScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
