# Releasing Halo

Halo's release script creates a native macOS app bundle, signs it, optionally submits it to Apple's notarization service, and writes a ZIP archive plus SHA-256 checksum.

## Local archive validation

An ad-hoc signature is sufficient to inspect the bundle locally:

```bash
HALO_VERSION=0.3.0 HALO_BUILD_NUMBER=1 ./script/package_release.sh
```

This is a validation artifact. Do not publish the ad-hoc-signed ZIP as an end-user download.

## Signed and notarized release

Prerequisites:

1. Install a valid `Developer ID Application` certificate in the login keychain.
2. Store App Store Connect credentials with `xcrun notarytool store-credentials`, choosing a keychain profile name.
3. Use a stable reverse-DNS bundle identifier.

Build, sign, notarize, and staple:

```bash
HALO_BUNDLE_ID=io.github.zeiprone.Halo \
HALO_VERSION=0.3.0 \
HALO_BUILD_NUMBER=1 \
HALO_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
HALO_NOTARY_PROFILE="halo-notary" \
./script/package_release.sh
```

The script stops on signing, notarization, stapling, or validation failures. It prints the final archive and checksum paths only after all requested checks succeed.

## Publish on GitHub

1. Confirm `swift test` and the `CI` workflow pass.
2. Update `CHANGELOG.md`, removing the release's entries from `Unreleased`.
3. Commit the release changes and create an annotated tag such as `v0.3.0`.
4. Create a GitHub release from the tag.
5. Attach both `Halo-<version>-macOS.zip` and its `.sha256` file from `dist/release/`.
6. Install the published ZIP on a second Mac and verify Spotify Automation, audio-capture permission, lyrics, and notch playback controls.
