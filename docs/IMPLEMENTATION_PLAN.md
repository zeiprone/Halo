# Halo Implementation Plan

## Phase 0: Repository and Feasibility

Completed:

- Created SwiftPM project structure.
- Investigated LRCLIB, SpotifyLyrics, Atoll, Apple CoreAudio process taps.
- Documented lock-screen and audio-capture risks.

## Phase 1: Spotify MVP

Completed:

- Menu bar app shell.
- Real Spotify AppleScript metadata provider.
- Playback interpolation.
- Play/pause, previous, and next commands.
- Studio dashboard.
- Transparent desktop lyrics and ambient overlay managers.
- Album artwork loading and palette extraction.
- Seek control in the expanded notch player.

Remaining:

- Better permission diagnostics UI.
- Launch-at-login support.

## Phase 2: Lyrics MVP

Completed:

- LRCLIB provider.
- Memory and disk cache.
- LRC parser with line and enhanced word timestamp support.
- Editorial, focus, and fisheye lyric presentations with previous/current/next lines.
- Fisheye presentation with perspective transitions.
- Real word-timestamp highlighting and complete-line rendering when word timing is unavailable.
- Manual offset UI.
- Persistent per-track offsets.

Remaining:

- Candidate search and selection.
- Better plain-lyrics browsing.

## Phase 3: Ambient Lighting

Completed:

- Ambient perimeter overlay.
- Testable audio feature extraction.
- Permission-gated Spotify CoreAudio process tap.
- Audio-reactive brightness, bass expansion, and transient response.
- Album artwork palette extraction and custom color controls.
- Multi-display overlays and reduced-motion controls.

Remaining:

- On-device tuning across built-in, wired, and Bluetooth audio routes.
- Low-power-mode frame-rate adaptation.

## Phase 4: Lock Screen

Current state:

- Disabled by default.

Next steps:

- Create an isolated experimental adapter.
- Manually test lock, unlock, sleep, wake, and user switching.
- Keep unsupported/private APIs out of the default product path.
