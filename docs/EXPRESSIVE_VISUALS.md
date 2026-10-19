# Expressive visuals (0.3)

The overlay hosts keep stable SwiftUI roots. A 60 Hz common-run-loop timer updates playback interpolation and the shared visual envelope; network lookup, palette loading and display reconciliation run on a separate 500 ms cadence. App startup no longer depends on opening the menu-bar popover.

Lyrics default to a centered editorial composition. Serif and heavy sans-serif treatments alternate by line, with a colored typographic emphasis and bounded audio-driven scale, rotation and glow. Real word timestamps control word highlighting when present. Line-only lyrics are shown as complete lines, without the previous artificial karaoke wipe. Untimed lyrics remain readable in Studio without pretending to be synchronized.

Lyrics lookup tries the exact recording and then searches compatible title/artist/duration candidates. It permits remaster suffix variation, rejects incompatible durations and artists, separates release cache keys, clears old lyrics immediately and retries temporary errors with a bounded backoff. Not every recording is available from LRCLIB.

Lights support one, two or three colors, artwork palettes, custom colors, Flow/Ribbons/Pulse patterns, beat impact and an independent Drop burst strength. The drop detector compares current RMS and bass against recent energy, holds a short envelope and prevents repeated burst retriggers within 750 ms. This is an audio-onset response, not a semantic drop predictor or a BPM estimator. Reduced motion disables burst expansion and travel.

CoreAudio transient events are latched until the visual consumer reads them. The callback uses a nonblocking mailbox write; stale features decay to silence. Spotify capture remains in memory and uses an unmuted mono process tap.

The app icon is packaged by Apple's iconutil. The bundle, running application and menu-bar item all use the supplied artwork.

## Verification

- 18 tests passed, including search recovery, remaster versus live matching, release cache isolation, bass discrimination and burst decay/pause reset.
- Native SwiftUI renders at 1440x900 and 1024x640 were inspected.
- The high-energy/drop fixture increased mean perimeter brightness by 3.1x versus the resting fixture.
- Finder's resolved app icon was decoded and visually checked; the ICNS has ten representations.
- The installed Desktop app recognized the current Spotify track and loaded 70 synchronized lines. Spotify was paused, so actual playing-audio reaction was not verified in this run.

Debug checks: `./script/build_and_run.sh --render-check` writes render fixtures to `/private/tmp/halo-visual-check`. Launching the bundle with `--smoke-check` writes an eight-second metadata/audio-state report to `/private/tmp/halo-smoke-check.json`. Neither check changes Spotify playback.
