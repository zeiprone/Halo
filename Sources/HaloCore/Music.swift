import AppKit
import Foundation

public enum PlaybackState: String, Codable, Sendable, Equatable {
    case playing
    case paused
    case stopped
    case unavailable
}

public struct Track: Codable, Sendable, Equatable, Identifiable {
    public var id: String { identity }

    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkURL: URL?
    public let identity: String

    public init(title: String, artist: String, album: String = "", duration: TimeInterval, artworkURL: URL? = nil, identity: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.identity = identity ?? [artist, title, album, String(Int(duration.rounded()))]
            .joined(separator: "|")
            .lowercased()
    }
}

public struct PlaybackObservation: Sendable, Equatable {
    public let track: Track?
    public let state: PlaybackState
    public let position: TimeInterval
    public let observedAt: ContinuousClock.Instant
    public let statusMessage: String?

    public init(
        track: Track?,
        state: PlaybackState,
        position: TimeInterval,
        observedAt: ContinuousClock.Instant = .now,
        statusMessage: String? = nil
    ) {
        self.track = track
        self.state = state
        self.position = position
        self.observedAt = observedAt
        self.statusMessage = statusMessage
    }
}

public protocol MusicProvider: Sendable {
    func observePlayback() async throws -> PlaybackObservation
    func playPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func seek(to position: TimeInterval) async throws
}

public enum SpotifyProviderError: LocalizedError, Sendable {
    case notRunning
    case automationDenied(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            "Spotify is not running."
        case .automationDenied(let message):
            "Spotify Automation permission is unavailable: \(message)"
        case .invalidResponse(let response):
            "Spotify returned an unexpected response: \(response)"
        }
    }
}

public struct SpotifyProvider: MusicProvider {
    public init() {}

    public func observePlayback() async throws -> PlaybackObservation {
        guard Self.isSpotifyRunning else {
            return PlaybackObservation(track: nil, state: .unavailable, position: 0, statusMessage: "Spotify is not running.")
        }

        let script = """
        tell application "Spotify"
            if player state is stopped then
                return "stopped||||||||||||"
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            set pState to player state as string
            set artUrl to artwork url of current track
            set trackIdentifier to id of current track
            return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & (trackDuration / 1000) & "|||" & trackPosition & "|||" & pState & "|||" & artUrl & "|||" & trackIdentifier
        end tell
        """

        let response = try await runAppleScript(script)
        let parts = response.components(separatedBy: "|||")
        guard parts.count >= 6 else { throw SpotifyProviderError.invalidResponse(response) }

        let stateText = parts[5].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if stateText == "stopped" {
            return PlaybackObservation(track: nil, state: .stopped, position: 0)
        }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Self.parseAppleScriptNumber(parts[3])
        let position = Self.parseAppleScriptNumber(parts[4])
        let artworkURL = parts.count > 6 ? URL(string: parts[6].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        let spotifyID = parts.count > 7 ? parts[7].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let state: PlaybackState = stateText.contains("playing") ? .playing : .paused

        let track = Track(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURL,
            identity: spotifyID.isEmpty ? nil : spotifyID
        )

        return PlaybackObservation(track: track, state: state, position: position)
    }

    public func playPause() async throws {
        _ = try await runAppleScript(#"tell application "Spotify" to playpause"#)
    }

    public func nextTrack() async throws {
        _ = try await runAppleScript(#"tell application "Spotify" to next track"#)
    }

    public func previousTrack() async throws {
        _ = try await runAppleScript(#"tell application "Spotify" to previous track"#)
    }

    public func seek(to position: TimeInterval) async throws {
        _ = try await runAppleScript("""
        tell application "Spotify"
            set player position to \(max(0, position))
        end tell
        """)
    }

    public static var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    public static func parseAppleScriptNumber(_ raw: String) -> TimeInterval {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return TimeInterval(normalized) ?? 0
    }

    private func runAppleScript(_ source: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let script = NSAppleScript(source: source)
            var error: NSDictionary?
            let descriptor = script?.executeAndReturnError(&error)

            if let error {
                let message = (error[NSAppleScript.errorMessage] as? String) ?? error.description
                throw SpotifyProviderError.automationDenied(message)
            }

            return descriptor?.stringValue ?? ""
        }.value
    }
}

public actor MockMusicProvider: MusicProvider {
    private var observations: [PlaybackObservation]
    public private(set) var commands: [String] = []

    public init(observations: [PlaybackObservation]) {
        self.observations = observations
    }

    public func observePlayback() async throws -> PlaybackObservation {
        if observations.count > 1 {
            return observations.removeFirst()
        }
        return observations.first ?? PlaybackObservation(track: nil, state: .stopped, position: 0)
    }

    public func playPause() async throws { commands.append("playPause") }
    public func nextTrack() async throws { commands.append("nextTrack") }
    public func previousTrack() async throws { commands.append("previousTrack") }
    public func seek(to position: TimeInterval) async throws { commands.append("seek:\(position)") }
}
