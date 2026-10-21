# Halo roadmap

This roadmap describes the areas currently worth improving. It is not a commitment or a release schedule; please open an issue before investing in a substantial contribution.

## Now

- Publish a Developer ID-signed, Apple-notarized DMG release and verify it on a second Mac.
- Exercise Spotify and YouTube Music playback, permissions, lyrics, and audio-reactive lighting on real user setups.
- Improve first-run guidance and diagnostics for Apple Events, Safari browser access, and system-audio capture.

## Next

- Add more visual regression coverage for overlays, notch-player states, and accessibility settings.
- Improve lyric matching, unavailable-lyrics feedback, and per-track timing adjustments.
- Expand playback-provider reliability while preserving the local-first privacy model.

## Later

- Make releases easier to install and update after the signed distribution path is stable.
- Consider translations and localization once the primary setup and support flow is proven.

## Contribution boundaries

Halo is deliberately local-first. Changes that add telemetry, accounts, audio uploads, remote control, or a new third-party music service require an issue and maintainer agreement before implementation.
