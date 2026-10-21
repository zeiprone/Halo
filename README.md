# Halo

Halo is a native macOS menu bar companion for Spotify. It shows time-synced lyrics and optional audio-reactive ambient lighting while Spotify remains the playback app.

**Downloads:** [GitHub Releases](https://github.com/zeiprone/Halo/releases) — signed and notarized DMG installers will be published here.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
[![CI](https://github.com/zeiprone/Halo/actions/workflows/ci.yml/badge.svg)](https://github.com/zeiprone/Halo/actions/workflows/ci.yml)

## What it does

- Reads local Spotify playback metadata and provides playback controls through macOS Automation.
- Fetches lyrics from [LRCLIB](https://lrclib.net/) and renders synchronized lyrics when available.
- Displays optional, click-through lyrics and ambient-lighting overlays.
- Includes a mini player docked to the MacBook notch. Hover to reveal playback controls; the menu bar toggle hides it.
- Analyses Spotify audio in memory only when Audio Reactive mode is enabled.

Halo is an independent project and is not affiliated with Spotify. Spotify is required and its desktop app must be running.

## Requirements

- macOS 15 or later
- Xcode 16 or later, including Command Line Tools
- Spotify desktop app

## Run from source

```bash
git clone https://github.com/zeiprone/Halo.git
cd Halo
./script/build_and_run.sh
```

The script builds a local `dist/Halo.app` bundle and launches it. The first use of Spotify controls or audio-reactive lighting may prompt for macOS permissions.

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

## Privacy

Halo has no accounts, analytics, backend, audio uploads, or audio recording. Spotify audio analysis stays in memory. Lyrics are requested from LRCLIB using the current track metadata; cached lyric timelines are stored in your macOS cache directory.

See [the architecture notes](docs/ARCHITECTURE.md) for the design and [the feasibility notes](docs/FEASIBILITY.md) for platform and third-party-service considerations.

## Contributing

Bug reports, documentation improvements, tests, and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please do not report vulnerabilities in public issues. See [SECURITY.md](SECURITY.md) for the reporting process.

## License

Halo is released under the [MIT License](LICENSE).
