#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${AME_DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="Ame.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SAVER_STAGING_DIR="$DIST_DIR/.saver-staging"
VERSION="${AME_VERSION:-0.1.0}"
BUILD_NUMBER="${AME_BUILD_NUMBER:-1}"
BUNDLE_ID="${AME_BUNDLE_ID:-org.ame.app}"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -n "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR
fi

cd "$ROOT_DIR"

swift build --disable-sandbox -c release

rm -rf "$SAVER_STAGING_DIR"
AME_SAVER_DEST_DIR="$SAVER_STAGING_DIR" \
  AME_OPEN_SETTINGS=0 \
  "$ROOT_DIR/scripts/install-screensaver.sh"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

ditto "$ROOT_DIR/.build/release/ame" "$MACOS_DIR/Ame"
chmod 755 "$MACOS_DIR/Ame"

ditto "$SAVER_STAGING_DIR/Ame.saver" "$RESOURCES_DIR/Ame.saver"
ditto "$ROOT_DIR/config/config.example.toml" "$RESOURCES_DIR/config.example.toml"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Ame</string>
	<key>CFBundleExecutable</key>
	<string>Ame</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Ame</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST

cat > "$CONTENTS_DIR/PkgInfo" <<PKGINFO
APPL????
PKGINFO

echo "Packaged $APP_DIR"
echo "Run it with: open \"$APP_DIR\""
