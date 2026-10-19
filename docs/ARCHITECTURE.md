# Halo Architecture

Halo is a native SwiftUI/AppKit macOS menu bar app. Spotify remains the playback engine; Halo observes playback, loads lyrics, and renders visual overlays.

## Modules

- `Halo`: app shell, menu bar UI, Studio window, overlay windows.
- `HaloCore`: testable music, playback, lyrics, audio-analysis, appearance, and lock-screen abstractions.

## Playback

`PlaybackCoordinator` is the single authoritative playback state. It receives periodic `PlaybackObservation` values from a `MusicProvider`, stores the latest position and observation timestamp, and interpolates current position using `ContinuousClock`.

Lyrics and overlays consume `PlaybackCoordinator`; they do not query Spotify independently.

## Spotify

`SpotifyProvider` uses AppleScript via Apple Events. It reads track metadata and playback state in one round trip and exposes commands for play/pause, previous, next, and seeking.

## Lyrics

`LyricsProvider` abstracts lyric sources. `LRCLIBProvider` is the first concrete provider. `LyricsManager` cancels stale requests on track changes, preventing slow lyrics responses from replacing the current song.

`LRCParser` returns structured `LyricsTimeline`, `LyricLine`, and `LyricWord` values.

## Rendering

Desktop overlays are transparent non-activating `NSPanel` windows:

- Lyrics overlay: SwiftUI `EditorialLyricsView`, with editorial, focus, and fisheye presentation modes.
- Ambient overlay: one click-through perimeter gradient per connected display.
- Notch player: an interactive status-level panel with compact and expanded layouts.

`SpotifyAudioCaptureEngine` owns the CoreAudio process tap and private aggregate device. Its real-time callback publishes only smoothed audio features; SwiftUI never receives or stores raw audio samples. Capture runs only while Spotify is playing and Audio Reactive mode is enabled.

Window levels are intentionally conservative. Lock-screen rendering is behind `LockScreenAdapter` and disabled by default.

## Privacy

Halo has no analytics, account system, backend, audio uploads, or audio recording. Spotify Automation and audio capture permissions are requested only for features that need them.
