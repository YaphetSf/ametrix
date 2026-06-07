#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DMG_PATH="${AMETRIX_DMG_PATH:-$ROOT_DIR/dist/Ametrix.dmg}"
NOTARY_PROFILE="${AMETRIX_NOTARY_PROFILE:-ametrix-notary}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
SUBMISSION_ID="${1:-${AMETRIX_NOTARY_SUBMISSION_ID:-}}"

if [[ -z "$SUBMISSION_ID" ]]; then
  echo "Error: submission id is required."
  echo "Usage: scripts/release/check-notarization.sh SUBMISSION_ID"
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: DMG not found: $DMG_PATH"
  exit 1
fi

if [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
  INFO="$(xcrun notarytool info "$SUBMISSION_ID" \
    --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" 2>&1)" || { echo "$INFO"; exit 1; }
elif ! INFO="$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
  echo "$INFO"
  exit 1
fi
echo "$INFO"

STATUS="$(printf "%s\n" "$INFO" | awk -F': ' '/status:/ { print $2; exit }')"

case "$STATUS" in
  Accepted)
    echo "Stapling notarization ticket to $DMG_PATH..."
    xcrun stapler staple "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
    echo "Notarized DMG is ready: $DMG_PATH"
    ;;
  "In Progress")
    echo "Notarization is still in progress. Check again later."
    exit 2
    ;;
  Invalid|Rejected)
    echo "Notarization failed. Fetching log..."
    if [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
      xcrun notarytool log "$SUBMISSION_ID" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID"
    else
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    fi
    exit 1
    ;;
  *)
    echo "Unknown notarization status: ${STATUS:-<empty>}"
    exit 1
    ;;
esac
