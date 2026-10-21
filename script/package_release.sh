#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Halo"
BUNDLE_ID="${HALO_BUNDLE_ID:-io.github.zeiprone.Halo}"
VERSION="${HALO_VERSION:-0.3.0}"
BUILD_NUMBER="${HALO_BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="15.0"
SIGN_IDENTITY="${HALO_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${HALO_NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME-package.XXXXXX")"
APP_BUNDLE="$PACKAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/Halo.entitlements"
ARCHIVE="$RELEASE_DIR/$APP_NAME-$VERSION-macOS.zip"
DMG="$RELEASE_DIR/$APP_NAME-$VERSION-macOS.dmg"
ARCHIVE_CHECKSUM="$ARCHIVE.sha256"
DMG_CHECKSUM="$DMG.sha256"

cleanup() {
  rm -rf "$PACKAGE_DIR"
}
trap cleanup EXIT

if [[ -n "$NOTARY_PROFILE" && -z "$SIGN_IDENTITY" ]]; then
  echo "HALO_NOTARY_PROFILE requires HALO_SIGN_IDENTITY." >&2
  exit 2
fi

mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build -c release --product "$APP_NAME"
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Halo needs permission to communicate with Spotify for local playback metadata and controls.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Halo uses system audio capture only when audio-reactive ambient lighting is enabled.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Halo contributors.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" "$ENTITLEMENTS"
xattr -cr "$APP_BUNDLE"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

package_archive() {
  rm -f "$ARCHIVE"
  ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP_BUNDLE" "$ARCHIVE"
}

package_dmg() {
  local staging_dir
  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME-dmg.XXXXXX")"
  trap 'rm -rf "$staging_dir"' RETURN

  ditto "$APP_BUNDLE" "$staging_dir/$APP_NAME.app"
  ln -s /Applications "$staging_dir/Applications"
  rm -f "$DMG"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$DMG"

  rm -rf "$staging_dir"
  trap - RETURN
}

package_archive

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
  package_archive
fi

package_dmg

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE_CHECKSUM")"
  shasum -a 256 "$(basename "$DMG")" >"$(basename "$DMG_CHECKSUM")"
)

echo "$ARCHIVE"
echo "$ARCHIVE_CHECKSUM"
echo "$DMG"
echo "$DMG_CHECKSUM"
