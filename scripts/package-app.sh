#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${AMETRIX_DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="Ametrix.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SAVER_STAGING_DIR="$DIST_DIR/.saver-staging"
VERSION="${AMETRIX_VERSION:-0.1.0}"
BUILD_NUMBER="${AMETRIX_BUILD_NUMBER:-1}"
BUNDLE_ID="${AMETRIX_BUNDLE_ID:-com.dingz.uk.ametrix.app}"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -n "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR
fi

cd "$ROOT_DIR"

swift build --disable-sandbox -c release

rm -rf "$SAVER_STAGING_DIR"
AMETRIX_SAVER_DEST_DIR="$SAVER_STAGING_DIR" \
  AMETRIX_OPEN_SETTINGS=0 \
  "$ROOT_DIR/scripts/install-screensaver.sh"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

ditto "$ROOT_DIR/.build/release/ametrix" "$MACOS_DIR/Ametrix"
chmod 755 "$MACOS_DIR/Ametrix"

ditto "$SAVER_STAGING_DIR/Ametrix.saver" "$RESOURCES_DIR/Ametrix.saver"
ditto "$ROOT_DIR/config/config.example.toml" "$RESOURCES_DIR/config.example.toml"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Ametrix</string>
	<key>CFBundleExecutable</key>
	<string>Ametrix</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Ametrix</string>
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
