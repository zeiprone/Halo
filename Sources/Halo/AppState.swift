import AppKit
import Foundation
import HaloCore
import SwiftUI

@MainActor
final class VisualMotion: ObservableObject {
    private(set) var position = 0.0
    private(set) var energy = 0.0
    private(set) var bass = 0.0
    private(set) var beat = 0.0
    private(set) var phase = 0.0
    private(set) var burst = 0.0
    @Published private(set) var revision = 0
    private var impactDetector = MusicImpactDetector()
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var loudnessReference = 0.06
    private var bassReference = 0.035

    func resetForTrack() {
        impactDetector = MusicImpactDetector()
        loudnessReference = 0.06
        bassReference = 0.035
        energy = 0
        bass = 0
        beat = 0
        burst = 0
    }

    func update(position: Double, features: AudioFeatures, playing: Bool, settings: VisualSettings) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - lastTime))
        lastTime = now
        self.position = position
        burst = impactDetector.update(features: features, deltaTime: dt, playing: playing)
        if playing {
            // Tracks are mastered at very different levels. Slowly learn each
            // track's floor so a quiet master remains as expressive as a loud one.
            let referenceAttack = 1 - exp(-dt / 1.8)
            let referenceRelease = 1 - exp(-dt / 4.0)
            let rms = Double(features.rms)
            let bassValue = Double(features.lowFrequencyEnergy)
            let rmsRate = rms > loudnessReference ? referenceAttack : referenceRelease
            let bassRate = bassValue > bassReference ? referenceAttack : referenceRelease
            loudnessReference += (rms - loudnessReference) * rmsRate
            bassReference += (bassValue - bassReference) * bassRate
        }
        let normalizedRMS = min(1, Double(features.rms) / max(0.022, loudnessReference * 0.92))
        let normalizedBass = min(1, Double(features.lowFrequencyEnergy) / max(0.012, bassReference * 0.92))
        let target = playing ? min(1, normalizedRMS * 0.82 * settings.sensitivity) : 0
        let bassTarget = playing ? min(1, normalizedBass * 0.9 * settings.sensitivity) : 0
        energy += (target - energy) * (1 - exp(-dt / (target > energy ? 0.028 : 0.18)))
        bass += (bassTarget - bass) * (1 - exp(-dt / (bassTarget > bass ? 0.025 : 0.2)))
        beat = playing && features.transient ? 1 : beat * exp(-dt / 0.18)
        if !settings.reducedMotion && settings.ambientMode != .staticLight {
            let drive = settings.ambientMode == .audioReactive ? energy * 0.6 + beat * 0.35 : 0.22
            phase += dt * settings.speed * (0.07 + drive)
        }
        revision &+= 1
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var showLyrics = true {
        didSet { overlayManager.setLyricsVisible(showLyrics) }
    }
    @Published var showAmbient = true {
        didSet { overlayManager.setAmbientVisible(showAmbient); updateAudioCaptureState() }
    }
    @Published var showNotchIsland = UserDefaults.standard.object(forKey: "showNotchIsland") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showNotchIsland, forKey: "showNotchIsland")
            if !showNotchIsland { isNotchIslandExpanded = false }
            overlayManager.setNotchIslandVisible(showNotchIsland)
        }
    }
    @Published private(set) var isNotchIslandExpanded = false
    @Published var settings = VisualSettings.load() {
        didSet {
            settings.save()
            overlayManager.repositionLyrics()
            overlayManager.setArtworkVisible(settings.showArtwork)
            updateAudioCaptureState()
        }
    }
    @Published var lyricsOffset = 0.0 {
        didSet {
            if let id = playback.currentTrack?.identity { UserDefaults.standard.set(lyricsOffset, forKey: "offset." + id) }
        }
    }
    @Published private(set) var albumPalette = HaloPalette.fallback
    @Published private(set) var albumArtwork: NSImage?
    @Published private(set) var audioStatus = "Waiting for playback"
    let playback = PlaybackCoordinator(provider: AutomaticMusicProvider())
    let lyrics = LyricsManager(provider: LRCLIBProvider())
    let motion = VisualMotion()
    let overlayManager = OverlayManager()
    let lockScreenAdapter = SafeLockScreenAdapter()
    let audioCapture = AppAudioCaptureEngine()
    private var trackID: String?
    private var paletteTask: Task<Void, Never>?
    private var captureRequested = false
    private var started = false
    private var nextServiceTime = 0.0
    private var nextCaptureAttempt = 0.0

    var colors: [Color] {
        let hexes = settings.useAlbumColors
            ? [albumPalette.primaryHex, albumPalette.secondaryHex, albumPalette.thirdHex]
            : [settings.primaryHex, settings.secondaryHex, settings.thirdHex]
        return Array(hexes.prefix(settings.colorCount)).map { Color(hex: $0) }
    }

    func start() {
        guard !started else { return }
        started = true
        playback.start()
        overlayManager.configure(state: self)
        overlayManager.setLyricsVisible(showLyrics)
        overlayManager.setAmbientVisible(showAmbient)
        overlayManager.setArtworkVisible(settings.showArtwork)
        overlayManager.setNotchIslandVisible(showNotchIsland)
    }

    func stop() {
        playback.stop()
        audioCapture.stop()
        paletteTask?.cancel()
    }

    func toggleNotchIsland() {
        showNotchIsland.toggle()
    }

    func hideArtwork() {
        guard settings.showArtwork else { return }
        settings.showArtwork = false
    }

    func setNotchIslandExpanded(_ expanded: Bool) {
        guard showNotchIsland, isNotchIslandExpanded != expanded else { return }
        isNotchIslandExpanded = expanded
        overlayManager.repositionNotchIsland()
    }

    func tick() {
        motion.update(position: playback.interpolatedPosition + lyricsOffset,
                      features: audioCapture.latestFeatures(), playing: playback.playbackState == .playing,
                      settings: settings)
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextServiceTime else { return }
        nextServiceTime = now + 0.5
        lyrics.loadLyrics(for: playback.currentTrack)
        if trackID != playback.currentTrack?.identity {
            trackID = playback.currentTrack?.identity
            motion.resetForTrack()
            lyricsOffset = trackID.map { UserDefaults.standard.double(forKey: "offset." + $0) } ?? 0
            loadPalette()
        }
        updateAudioCaptureState()
        if audioStatus != audioCapture.status { audioStatus = audioCapture.status }
        overlayManager.refreshDisplays()
    }

    func retryLyrics() { lyrics.loadLyrics(for: playback.currentTrack, force: true) }

    private func updateAudioCaptureState() {
        guard started else { return }
        let shouldCapture = playback.playbackState == .playing
            && ((showAmbient && settings.ambientMode == .audioReactive) || (showLyrics && settings.syncTypography))
        let now = ProcessInfo.processInfo.systemUptime
        if shouldCapture && !audioCapture.isRunning && now >= nextCaptureAttempt {
            nextCaptureAttempt = now + 1.5
            audioCapture.start(for: playback.observation.source)
        } else if !shouldCapture && captureRequested {
            audioCapture.stop()
            nextCaptureAttempt = 0
        }
        captureRequested = shouldCapture
    }

    private func loadPalette() {
        paletteTask?.cancel()
        albumPalette = .fallback
        albumArtwork = nil
        guard let track = playback.currentTrack, let url = track.artworkURL else { return }
        paletteTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, let image = NSImage(data: data), trackID == track.identity else { return }
            albumArtwork = image
            albumPalette = AlbumColorExtractor.palette(from: image)
            overlayManager.updateArtwork()
        }
    }
}
