#!/usr/bin/env bash
# Build, sign, notarize, package into dist/Ametrix-<version>-universal.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=Release
APP_NAME="Ametrix"
ENTITLEMENTS="$ROOT/scripts/entitlements.plist"
DERIVED=".build/ReleaseDerivedData"
STAGE=".build/stage"
DMG_ROOT="$STAGE/dmg"
OUT="dist"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "$VERSION" ] || { echo "could not read MARKETING_VERSION from project.yml" >&2; exit 1; }

NOTARY_PROFILE="${AMETRIX_NOTARY_PROFILE:-}"
SKIP_NOTARIZE="${AMETRIX_SKIP_NOTARIZE:-0}"

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen missing" >&2; exit 1; }

if [ "$SKIP_NOTARIZE" = "1" ]; then
  IDENTITY=-
  DMG_PATH="$OUT/Ametrix-$VERSION-preview.dmg"
else
  [ -n "$NOTARY_PROFILE" ] || { echo "AMETRIX_NOTARY_PROFILE required for notarization" >&2; exit 1; }
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || { echo "invalid notary profile: $NOTARY_PROFILE" >&2; exit 1; }
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  [ -n "$IDENTITY" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
  DMG_PATH="$OUT/Ametrix-$VERSION-universal.dmg"
fi

sign() {
  if [ "$IDENTITY" = - ]; then
    codesign --force --timestamp=none --options runtime --sign - "$@"
  else
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"
  fi
}

echo "==> xcodegen"
xcodegen generate --quiet

echo "==> xcodebuild ($CONFIG, identity: $IDENTITY)"
xcodebuild -project ametrix.xcodeproj -scheme ametrix -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
  -quiet build 2>&1 | { grep -v DVTDeviceOperation || true; }

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }

for binary in \
  "$APP/Contents/MacOS/$APP_NAME" \
  "$APP/Contents/Resources/$APP_NAME.saver/Contents/MacOS/$APP_NAME"; do
  architectures="$(lipo -archs "$binary")"
  if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
    echo "Error: expected Universal 2, got '$architectures': $binary" >&2
    exit 1
  fi
done

echo "==> stage"
rm -rf "$STAGE" "$OUT"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

echo "==> sign"
EMBEDDED="$DMG_ROOT/$APP_NAME.app/Contents/Resources/$APP_NAME.saver"
sign --entitlements "$ENTITLEMENTS" "$EMBEDDED"
sign --entitlements "$ENTITLEMENTS" "$DMG_ROOT/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/$APP_NAME.app"

echo "==> DMG"
mkdir -p "$OUT"
hdiutil create -volname "Ametrix $VERSION" -srcfolder "$DMG_ROOT" \
  -ov -format UDZO -imagekey zlib-level=9 -quiet "$DMG_PATH"

if [ "$SKIP_NOTARIZE" = "1" ]; then
  codesign --force --timestamp=none --sign - "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
  echo "Preview DMG (ad-hoc, not for distribution): $DMG_PATH"
  exit 0
fi

echo "==> sign DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"

echo "==> notarize"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"

echo "Notarized DMG: $DMG_PATH"
