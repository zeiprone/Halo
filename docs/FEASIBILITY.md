# Halo Feasibility

Date: 2026-09-21

## Summary

The desktop lyrics and ambient overlay MVP is feasible with public macOS APIs. Real Spotify playback metadata can be read through Apple Events, synchronized lyrics can come from LRCLIB, and desktop overlays can be implemented with transparent non-activating AppKit panels. Lock-screen rendering is not considered production-ready yet because the most relevant reference implementation depends on unsupported/private behavior.

## A. Spotify Integration

Decision: use local Apple Events against the Spotify desktop app for Phase 1.

Verified reference behavior:

- SpotifyLyrics uses a stateless AppleScript bridge for metadata, player state, position, artwork URL, and playback commands. Its repo is MIT licensed.
- Atoll also queries Spotify through AppleScript for local metadata, and uses Spotify OAuth only for features like liked-song state and canvas metadata.

Implementation in this repo:

- `SpotifyProvider` checks `NSWorkspace.shared.runningApplications` before sending Apple Events, avoiding accidental Spotify launches.
- A single AppleScript round trip reads title, artist, album, duration, player position, state, artwork URL, and Spotify track id.
- `PlaybackCoordinator` owns the authoritative playback observation and interpolates position with `ContinuousClock` only while playing.
- Automation denial is surfaced as a clear error message.

Known limits:

- Apple Events require macOS Automation permission.
- Polling is currently 900 ms. That is conservative enough for personal use, but future work should tune intervals based on state and app visibility.
- Album artwork is downloaded from Spotify's artwork URL for local display and palette extraction. Artwork data is not uploaded.

## B. Lyrics Integration

Decision: use LRCLIB as the first provider behind a `LyricsProvider` protocol.

Verified API contract:

- LRCLIB provides `GET /api/get`.
- `track_name` and `artist_name` are required.
- `album_name` is recommended.
- `duration` is in seconds and materially improves matching; LRCLIB documents a tight duration match requirement.
- Clients must identify themselves with `User-Agent`, `X-User-Agent`, or `Lrclib-Client`.
- `429` responses include `Retry-After` and must be respected.

Implementation in this repo:

- `LRCLIBProvider` uses `/api/get`, sends a `User-Agent`, handles 404 as no lyrics, and throws on 429 with retry information.
- `LyricsCache` supports memory and disk cache.
- `LRCParser` supports line timestamps, multiple line timestamps, Unicode text, and enhanced inline word timestamps like `<mm:ss.xx>word`.
- Plain lyrics are displayed without fabricated timing.

Known limits:

- Candidate search automatically retries compatible title, artist, and duration matches. Manual candidate selection is not implemented.
- Per-track manual lyric offsets are persisted in local preferences.

## C. Lock-Screen Rendering

Decision: keep lock-screen content disabled in the safe default build.

Reference investigation:

- Atoll is GPL-3.0 and uses `SkyLightWindow` for lock-screen widget rendering.
- Atoll also uses private MediaRemote bindings for generalized now-playing control in some paths.
- Direct source reuse would either impose GPL obligations or require explicit license compliance. Halo currently treats Atoll as architectural research only.

Current implementation:

- `SafeLockScreenAdapter` reports lock-screen rendering as unsupported.
- The app does not disable SIP, modify protected system files, bypass authentication, or interfere with login.

Proof-of-concept status:

- Not attempted automatically because a real lock/unlock test cannot be safely verified from this environment.
- The next safe step is an explicitly enabled experimental adapter in a separate module after manual user consent and on-device lock/unlock testing.

## D. Audio Capture

Decision: use a permission-gated CoreAudio process tap for Spotify and analyze audio only in memory.

Verified API direction:

- Apple's CoreAudio process tap documentation describes `AudioHardwareCreateProcessTap` and requires macOS 14.2+.
- Apps must include `NSAudioCaptureUsageDescription`.
- Atoll uses process taps and aggregate devices, including Spotify-specific routing caveats.

Implementation in this repo:

- `SpotifyAudioCaptureEngine` resolves Spotify's CoreAudio process object, creates a private process tap and aggregate device, and tears them down when playback pauses or ambient lighting is disabled.
- `AudioAnalyzer` calculates RMS, peak, low-frequency energy, and transient candidates in memory.
- `AmbientLightingModel` maps features to brightness, expansion, and saturation.
- Album artwork colors drive the perimeter gradient by default, with custom color overrides available.
- One click-through ambient panel is maintained for every connected display.
- No audio is recorded to disk.

Known limits:

- Audio capture requires the user to approve the macOS audio-capture permission prompt.
- Process-tap behavior still needs a listening test with real Spotify playback and the user's active audio route.
