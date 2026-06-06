#!/usr/bin/env bash
# Clean-slate rebuild + relaunch for testing the app like a first-time user.
#
#   scripts/dev/retest.sh            full reset (prefs + saver + config), repackage, launch
#   scripts/dev/retest.sh --keep     keep installed saver + config, just reset prefs
#   scripts/dev/retest.sh --no-build skip repackaging (use existing dist/Ametrix.app)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_ID="com.dingz.uk.ametrix.app"
APP="$ROOT_DIR/dist/Ametrix.app"

KEEP=0
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    --no-build) BUILD=0 ;;
    *) echo "unknown arg: $arg"; exit 64 ;;
  esac
done

echo "==> killing running instances"
pkill -f "Ametrix" 2>/dev/null || true
sleep 1

echo "==> clearing preferences ($BUNDLE_ID)"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

if [[ "$KEEP" == "0" ]]; then
  echo "==> removing installed screen saver"
  rm -rf "$HOME/Library/Screen Savers/Ametrix.saver"
  echo "==> removing user config"
  rm -f "$HOME/Library/Application Support/Ametrix/config.toml"
  rm -f "$HOME/.config/ametrix/config.toml" 2>/dev/null || true
fi

if [[ "$BUILD" == "1" ]]; then
  echo "==> repackaging app"
  "$ROOT_DIR/scripts/release/package-app.sh" >/dev/null
fi

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found (run without --no-build)"; exit 1
fi

echo "==> launching $APP"
open "$APP"
sleep 2

# Accessory apps don't steal focus, so nudge the onboarding window to the front.
osascript -e 'tell application "System Events" to tell process "Ametrix" to set frontmost to true' 2>/dev/null || true

echo "==> done. Onboarding should be showing (look for the Welcome window)."
