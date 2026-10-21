import AppKit
import Foundation

public enum PlaybackState: String, Codable, Sendable, Equatable {
    case playing
    case paused
    case stopped
    case unavailable
}

public enum MusicSource: String, Codable, Sendable, Equatable {
    case spotify
    case youTubeMusicSafari
    case youTubeMusicChrome

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .youTubeMusicSafari, .youTubeMusicChrome: "YouTube Music"
        }
    }

    public var applicationBundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .youTubeMusicSafari: "com.apple.Safari"
        case .youTubeMusicChrome: "com.google.Chrome"
        }
    }
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
    public let source: MusicSource?
    public let observedAt: ContinuousClock.Instant
    public let statusMessage: String?

    public init(
        track: Track?,
        state: PlaybackState,
        position: TimeInterval,
        source: MusicSource? = nil,
        observedAt: ContinuousClock.Instant = .now,
        statusMessage: String? = nil
    ) {
        self.track = track
        self.state = state
        self.position = position
        self.source = source
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
            return PlaybackObservation(track: nil, state: .stopped, position: 0, source: .spotify)
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

        return PlaybackObservation(track: track, state: state, position: position, source: .spotify)
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

public enum YouTubeMusicProviderError: LocalizedError, Sendable {
    case automationDenied(String)
    case invalidResponse(String)
    case noActiveProvider

    public var errorDescription: String? {
        switch self {
        case .automationDenied(let message):
            "YouTube Music browser access is unavailable: \(message)"
        case .invalidResponse(let response):
            "YouTube Music returned an unexpected response: \(response)"
        case .noActiveProvider:
            "Start playback in Spotify or YouTube Music."
        }
    }
}

/// Reads an open music.youtube.com tab through the browser's documented AppleScript bridge.
/// This never signs in, sends listening data to Halo, or injects code into other websites.
public struct YouTubeMusicProvider: MusicProvider {
    private enum Browser: CaseIterable {
        case safari
        case chrome

        var applicationName: String {
            switch self {
            case .safari: "Safari"
            case .chrome: "Google Chrome"
            }
        }

        var bundleIdentifier: String {
            switch self {
            case .safari: "com.apple.Safari"
            case .chrome: "com.google.Chrome"
            }
        }

        var source: MusicSource {
            switch self {
            case .safari: .youTubeMusicSafari
            case .chrome: .youTubeMusicChrome
            }
        }
    }

    public init() {}

    public func observePlayback() async throws -> PlaybackObservation {
        for browser in Browser.allCases where Self.isRunning(browser) {
            let response = try await execute(Self.metadataJavaScript, in: browser)
            guard !response.isEmpty else { continue }
            return try Self.parse(response, source: browser.source)
        }
        return PlaybackObservation(
            track: nil,
            state: .unavailable,
            position: 0,
            statusMessage: "Open YouTube Music in Safari or Google Chrome."
        )
    }

    public func playPause() async throws { try await command("document.querySelector('#play-pause-button')?.click()") }
    public func nextTrack() async throws { try await command("document.querySelector('#next-button')?.click()") }
    public func previousTrack() async throws { try await command("document.querySelector('#previous-button')?.click()") }
    public func seek(to position: TimeInterval) async throws {
        try await command("const media = document.querySelector('video'); if (media) media.currentTime = \(max(0, position));")
    }

    static func parse(_ response: String, source: MusicSource) throws -> PlaybackObservation {
        let parts = response.components(separatedBy: "\u{1F}")
        guard parts.count >= 8 else { throw YouTubeMusicProviderError.invalidResponse(response) }
        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return PlaybackObservation(track: nil, state: .stopped, position: 0, source: source)
        }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = SpotifyProvider.parseAppleScriptNumber(parts[3])
        let position = SpotifyProvider.parseAppleScriptNumber(parts[4])
        let state: PlaybackState = parts[5].trimmingCharacters(in: .whitespacesAndNewlines) == "playing" ? .playing : .paused
        let artworkURL = URL(string: parts[6].trimmingCharacters(in: .whitespacesAndNewlines))
        let identity = parts[7].trimmingCharacters(in: .whitespacesAndNewlines)
        return PlaybackObservation(
            track: Track(title: title, artist: artist, album: album, duration: duration, artworkURL: artworkURL,
                         identity: identity.isEmpty ? nil : "ytm|\(identity)"),
            state: state,
            position: position,
            source: source
        )
    }

    private func command(_ javascript: String) async throws {
        for browser in Browser.allCases where Self.isRunning(browser) {
            let result = try await execute(javascript, in: browser)
            if !result.isEmpty { return }
        }
        throw YouTubeMusicProviderError.noActiveProvider
    }

    private func execute(_ javascript: String, in browser: Browser) async throws -> String {
        let quoted = Self.appleScriptString(javascript)
        let source: String
        switch browser {
        case .safari:
            source = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" then return do JavaScript \(quoted) in t
                    end repeat
                end repeat
            end tell
            return ""
            """
        case .chrome:
            source = """
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" then return execute t javascript \(quoted)
                    end repeat
                end repeat
            end tell
            return ""
            """
        }
        return try await runYouTubeMusicAppleScript(source)
    }

    private static func isRunning(_ browser: Browser) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == browser.bundleIdentifier }
    }

    private static func appleScriptString(_ value: String) -> String {
        let oneLine = value.replacingOccurrences(of: "\n", with: " ")
        let escaped = oneLine
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static let metadataJavaScript = """
    (() => {
      const player = document.querySelector('ytmusic-player-bar');
      const media = document.querySelector('video');
      const title = player?.querySelector('.title')?.textContent?.trim() || '';
      const artist = Array.from(player?.querySelectorAll('.byline a') || []).map(node => node.textContent.trim()).join(', ');
      const artwork = player?.querySelector('img')?.src || '';
      const clean = value => String(value ?? '').replaceAll('\\u001F', ' ');
      return [title, artist, '', media?.duration || 0, media?.currentTime || 0, media && !media.paused ? 'playing' : 'paused', artwork, location.href].map(clean).join('\\u001F');
    })()
    """
}

/// Chooses the source that is actively playing. Spotify wins only when both sources play simultaneously.
public actor AutomaticMusicProvider: MusicProvider {
    private let spotify = SpotifyProvider()
    private let youtubeMusic = YouTubeMusicProvider()
    private var activeSource: MusicSource?

    public init() {}

    public func observePlayback() async throws -> PlaybackObservation {
        let spotifyObservation = try? await spotify.observePlayback()
        let youtubeObservation = try? await youtubeMusic.observePlayback()
        let candidates = [spotifyObservation, youtubeObservation].compactMap { $0 }

        let selected = candidates.first(where: { $0.state == .playing })
            ?? candidates.first(where: { $0.state != .unavailable })

        guard let selected else {
            activeSource = nil
            return PlaybackObservation(
                track: nil,
                state: .unavailable,
                position: 0,
                statusMessage: "Start playback in Spotify or YouTube Music."
            )
        }
        activeSource = selected.source
        return selected
    }

    public func playPause() async throws { try await activeProvider().playPause() }
    public func nextTrack() async throws { try await activeProvider().nextTrack() }
    public func previousTrack() async throws { try await activeProvider().previousTrack() }
    public func seek(to position: TimeInterval) async throws { try await activeProvider().seek(to: position) }

    private func activeProvider() throws -> any MusicProvider {
        switch activeSource {
        case .spotify: spotify
        case .youTubeMusicSafari, .youTubeMusicChrome: youtubeMusic
        case nil: throw YouTubeMusicProviderError.noActiveProvider
        }
    }
}

private func runYouTubeMusicAppleScript(_ source: String) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let descriptor = script?.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? error.description
            throw YouTubeMusicProviderError.automationDenied(message)
        }
        return descriptor?.stringValue ?? ""
    }.value
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
