# Halo

Halo is a native macOS menu bar companion for Spotify and YouTube Music. It shows time-synced lyrics and optional audio-reactive ambient lighting while your music service remains the playback app.

**Downloads:** [GitHub Releases](https://github.com/zeiprone/Halo/releases) — signed and notarized DMG installers will be published here.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
[![CI](https://github.com/zeiprone/Halo/actions/workflows/ci.yml/badge.svg)](https://github.com/zeiprone/Halo/actions/workflows/ci.yml)

## Preview

Halo keeps your player in charge while bringing lyrics and reactive light to your desktop.

| Resting lyrics overlay | Audio-reactive lyrics overlay |
| --- | --- |
| ![Lyrics overlay at rest](docs/images/lyrics-overlay-rest.png) | ![Lyrics overlay responding to a beat](docs/images/lyrics-overlay-reactive.png) |

<p align="center">
  <img src="docs/images/lyrics-overlay-compact.png" alt="Compact lyrics overlay" width="640">
</p>

These previews are rendered by Halo's SwiftUI visual check with local fixture lyrics; they do not use a Spotify account or upload audio.

## What it does

- Reads local Spotify playback metadata and controls Spotify through macOS Automation.
- Reads and controls an open YouTube Music tab in Safari or Google Chrome through macOS Automation.
- Fetches lyrics from [LRCLIB](https://lrclib.net/) and renders synchronized lyrics when available.
- Displays optional, click-through lyrics and ambient-lighting overlays.
- Includes a mini player docked to the MacBook notch. Hover to reveal playback controls; the menu bar toggle hides it.
- Analyses the active player or browser audio in memory only when Audio Reactive mode is enabled.

Halo is an independent project and is not affiliated with Spotify, YouTube, or Google. Use either Spotify's desktop app or YouTube Music in Safari or Google Chrome.

## Requirements

- macOS 15 or later
- Spotify desktop app, or YouTube Music open in Safari or Google Chrome

Building from source additionally requires Xcode 16 or later, including Command Line Tools.

## Install a release

When a signed Halo release is available:

1. Open the latest [GitHub Release](https://github.com/zeiprone/Halo/releases) and download `Halo-<version>-macOS.dmg`.
2. Open the DMG and drag **Halo** into **Applications**.
3. Launch Halo, then start music in Spotify or in a YouTube Music tab.

The first public installer is still being prepared. Until then, use the source build below rather than an ad-hoc archive; only a Developer ID-signed and Apple-notarized DMG is suitable for end users.

## First-time setup

1. Start Spotify's desktop app, or open `music.youtube.com` in Safari or Google Chrome.
2. Launch Halo and allow macOS Automation access when prompted. This lets Halo read the active track and send playback controls only to your chosen player.
3. For YouTube Music in Safari, turn on **Develop → Allow JavaScript from Apple Events**. Chrome needs only the normal macOS Automation approval.
4. Enable **Lyrics overlay** or **Dynamic lights** from Halo's menu bar. macOS may request permission before system-audio analysis begins.

## Run from source

```bash
git clone https://github.com/zeiprone/Halo.git
cd Halo
./script/build_and_run.sh
```

The script builds a local `dist/Halo.app` bundle and launches it. The first use of player controls or audio-reactive lighting may prompt for macOS permissions. Safari users may also need to enable **Develop → Allow JavaScript from Apple Events** so Halo can read and control their YouTube Music tab.

Useful development commands:

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --render-check
```

To use a bundle identifier and version appropriate for a signed release, pass them through the environment:

```bash
HALO_BUNDLE_ID=io.github.example.Halo HALO_VERSION=0.3.0 HALO_BUILD_NUMBER=1 ./script/build_and_run.sh
```

Keep the bundle identifier stable between local builds. Changing it makes macOS treat Halo as a different app for Spotify Automation permissions.

## Build a release archive

Create an ad-hoc-signed archive for local validation:

```bash
./script/package_release.sh
```

The ZIP, drag-and-drop DMG, and SHA-256 checksums are written to `dist/release/`. Public downloads should be signed with a Developer ID certificate and notarized by Apple. Maintainer instructions are in [docs/RELEASING.md](docs/RELEASING.md).

## Troubleshooting

**Halo cannot see YouTube Music.** Keep a `music.youtube.com` tab open in Safari or Google Chrome, then grant Halo permission in **System Settings → Privacy & Security → Automation**. In Safari, also enable **Develop → Allow JavaScript from Apple Events**.

**Controls target the wrong service.** Halo chooses a source that is actively playing. If both Spotify and YouTube Music play at once, Spotify takes priority; pause the other service and Halo will switch on its next refresh.

**Dynamic lights react to unrelated browser sound.** YouTube Music audio is captured from its browser process, so sound from another tab in that same browser may influence the visual response. Use a separate browser profile/window, or pause other browser media.

**Lyrics are missing or out of time.** Halo queries LRCLIB using the current title and artist. Some tracks have no synced entry; use the Studio timing control to compensate for a known offset, then retry the lookup.

## Privacy

Halo has no accounts, analytics, backend, audio uploads, or audio recording. Player audio analysis stays in memory. Lyrics are requested from LRCLIB using the current track metadata; cached lyric timelines are stored in your macOS cache directory.

See [the architecture notes](docs/ARCHITECTURE.md) for the design and [the feasibility notes](docs/FEASIBILITY.md) for platform and third-party-service considerations.

## Contributing

Bug reports, documentation improvements, tests, and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please do not report vulnerabilities in public issues. See [SECURITY.md](SECURITY.md) for the reporting process.

## License

Halo is released under the [MIT License](LICENSE).
