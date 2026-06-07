#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="${AMETRIX_DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="Ametrix.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SAVER_STAGING_DIR="$DIST_DIR/.saver-staging"
UNIVERSAL_BUILD_DIR="$ROOT_DIR/.build/universal"
ARM64_BUILD_DIR="$ROOT_DIR/.build/swift-arm64"
X86_64_BUILD_DIR="$ROOT_DIR/.build/swift-x86_64"
VERSION="${AMETRIX_VERSION:-0.1.0}"
BUILD_NUMBER="${AMETRIX_BUILD_NUMBER:-1}"
BUNDLE_ID="${AMETRIX_BUNDLE_ID:-com.dingz.uk.ametrix.app}"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -n "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR
fi

cd "$ROOT_DIR"

swift build \
  --disable-sandbox \
  --configuration release \
  --scratch-path "$ARM64_BUILD_DIR" \
  --triple arm64-apple-macosx13.0

swift build \
  --disable-sandbox \
  --configuration release \
  --scratch-path "$X86_64_BUILD_DIR" \
  --triple x86_64-apple-macosx13.0

mkdir -p "$UNIVERSAL_BUILD_DIR"
lipo -create \
  "$ARM64_BUILD_DIR/arm64-apple-macosx/release/ametrix" \
  "$X86_64_BUILD_DIR/x86_64-apple-macosx/release/ametrix" \
  -output "$UNIVERSAL_BUILD_DIR/ametrix"

rm -rf "$SAVER_STAGING_DIR"
AMETRIX_SAVER_DEST_DIR="$SAVER_STAGING_DIR" \
  "$ROOT_DIR/scripts/release/build-screensaver.sh"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

ditto "$UNIVERSAL_BUILD_DIR/ametrix" "$MACOS_DIR/Ametrix"
chmod 755 "$MACOS_DIR/Ametrix"

ditto "$SAVER_STAGING_DIR/Ametrix.saver" "$RESOURCES_DIR/Ametrix.saver"
ditto "$ROOT_DIR/config/config.example.toml" "$RESOURCES_DIR/config.example.toml"
ditto "$ROOT_DIR/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

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
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
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

for binary in \
  "$MACOS_DIR/Ametrix" \
  "$RESOURCES_DIR/Ametrix.saver/Contents/MacOS/Ametrix"; do
  architectures="$(lipo -archs "$binary")"
  if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
    echo "Error: expected Universal 2 binary, found '$architectures': $binary"
    exit 1
  fi
done

echo "Packaged $APP_DIR"
echo "Architectures: arm64 x86_64"
echo "Run it with: open \"$APP_DIR\""
