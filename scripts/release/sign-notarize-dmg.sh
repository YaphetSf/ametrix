#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="${AMETRIX_DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/Ametrix.app"
DMG_STAGING_DIR="$DIST_DIR/.dmg-staging"
DMG_PATH="${AMETRIX_DMG_PATH:-$DIST_DIR/Ametrix.dmg}"
ENTITLEMENTS_PATH="${AMETRIX_ENTITLEMENTS_PATH:-$ROOT_DIR/scripts/release/entitlements.plist}"
SIGN_IDENTITY="${AMETRIX_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${AMETRIX_NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
SKIP_PACKAGE="${AMETRIX_SKIP_PACKAGE:-0}"
SKIP_NOTARIZE="${AMETRIX_SKIP_NOTARIZE:-0}"
WAIT_FOR_NOTARY="${AMETRIX_NOTARY_WAIT:-1}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Error: AMETRIX_SIGN_IDENTITY is required."
  echo "Example:"
  echo "  AMETRIX_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' scripts/release/sign-notarize-dmg.sh"
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "Error: entitlements file not found: $ENTITLEMENTS_PATH"
  exit 1
fi

cd "$ROOT_DIR"

if [[ "$SKIP_PACKAGE" != "1" ]]; then
  "$ROOT_DIR/scripts/release/package-app.sh"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Error: app bundle not found: $APP_DIR"
  echo "Run scripts/release/package-app.sh first, or leave AMETRIX_SKIP_PACKAGE unset."
  exit 1
fi

echo "Signing nested screen saver..."
codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$SIGN_IDENTITY" \
  "$APP_DIR/Contents/Resources/Ametrix.saver"

echo "Signing app..."
codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$SIGN_IDENTITY" \
  "$APP_DIR"

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR" || true

echo "Creating DMG..."
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_DIR" "$DMG_STAGING_DIR/Ametrix.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Ametrix" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Signing DMG..."
codesign \
  --force \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$DMG_PATH"

echo "Verifying DMG signature..."
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "Skipping notarization because AMETRIX_SKIP_NOTARIZE=1."
  echo "Created signed DMG: $DMG_PATH"
  exit 0
fi

echo "Submitting DMG for notarization..."
if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$WAIT_FOR_NOTARY" == "1" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  else
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE"
  fi
elif [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
  if [[ "$WAIT_FOR_NOTARY" == "1" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
  else
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID"
  fi
else
  echo "Error: notarization credentials are missing."
  echo "Set AMETRIX_NOTARY_PROFILE, or set APPLE_ID, APPLE_PASSWORD, and APPLE_TEAM_ID."
  echo "For a signed-only local build, rerun with AMETRIX_SKIP_NOTARIZE=1."
  exit 1
fi

if [[ "$WAIT_FOR_NOTARY" != "1" ]]; then
  echo "Notarization submitted without waiting."
  echo "Check and staple later with: scripts/release/check-notarization.sh SUBMISSION_ID"
  exit 0
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "Assessing notarized DMG..."
spctl --assess --type open --verbose=2 "$DMG_PATH"

echo "Created notarized DMG: $DMG_PATH"
