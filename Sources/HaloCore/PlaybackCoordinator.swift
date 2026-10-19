import Foundation

@MainActor
public final class PlaybackCoordinator: ObservableObject {
    @Published public private(set) var observation: PlaybackObservation
    @Published public private(set) var lastError: String?

    private let provider: MusicProvider
    private let pollInterval: Duration
    private var pollingTask: Task<Void, Never>?

    public init(provider: MusicProvider, pollInterval: Duration = .milliseconds(900)) {
        self.provider = provider
        self.pollInterval = pollInterval
        self.observation = PlaybackObservation(track: nil, state: .unavailable, position: 0, statusMessage: "Waiting for Spotify.")
    }

    deinit {
        pollingTask?.cancel()
    }

    public var currentTrack: Track? { observation.track }
    public var playbackState: PlaybackState { observation.state }

    public var interpolatedPosition: TimeInterval {
        interpolatedPosition(at: .now)
    }

    public func interpolatedPosition(at now: ContinuousClock.Instant) -> TimeInterval {
        guard observation.state == .playing else { return observation.position }
        let elapsed = observation.observedAt.duration(to: now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        let duration = observation.track?.duration ?? .greatestFiniteMagnitude
        return min(max(0, observation.position + seconds), duration)
    }

    public func apply(_ newObservation: PlaybackObservation) {
        observation = newObservation
        lastError = nil
    }

    public func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func refresh() async {
        do {
            let latest = try await provider.observePlayback()
            apply(latest)
        } catch {
            lastError = error.localizedDescription
            observation = PlaybackObservation(track: observation.track, state: .unavailable, position: observation.position, statusMessage: error.localizedDescription)
        }
    }

    public func playPause() {
        Task {
            try? await provider.playPause()
            await refresh()
        }
    }

    public func nextTrack() {
        Task {
            try? await provider.nextTrack()
            await refresh()
        }
    }

    public func previousTrack() {
        Task {
            try? await provider.previousTrack()
            await refresh()
        }
    }

    public func seek(to position: TimeInterval) {
        Task {
            try? await provider.seek(to: position)
            await refresh()
        }
    }
}
