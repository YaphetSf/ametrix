#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${AMETRIX_DMG_PATH:-$ROOT_DIR/dist/Ametrix.dmg}"
NOTARY_PROFILE="${AMETRIX_NOTARY_PROFILE:-ame-notary}"
SUBMISSION_ID="${1:-${AMETRIX_NOTARY_SUBMISSION_ID:-}}"

if [[ -z "$SUBMISSION_ID" ]]; then
  echo "Error: submission id is required."
  echo "Usage: scripts/check-notarization.sh SUBMISSION_ID"
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: DMG not found: $DMG_PATH"
  exit 1
fi

INFO="$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE")"
echo "$INFO"

STATUS="$(printf "%s\n" "$INFO" | awk -F': ' '/status:/ { print $2; exit }')"

case "$STATUS" in
  Accepted)
    echo "Stapling notarization ticket to $DMG_PATH..."
    xcrun stapler staple "$DMG_PATH"
    spctl --assess --type open --verbose=2 "$DMG_PATH"
    echo "Notarized DMG is ready: $DMG_PATH"
    ;;
  "In Progress")
    echo "Notarization is still in progress. Check again later."
    exit 2
    ;;
  Invalid|Rejected)
    echo "Notarization failed. Fetching log..."
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    exit 1
    ;;
  *)
    echo "Unknown notarization status: ${STATUS:-<empty>}"
    exit 1
    ;;
esac
