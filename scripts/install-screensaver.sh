#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
PRODUCT="$DERIVED_DATA/Build/Products/Release/Ame.saver"
DEST_DIR="${AME_SAVER_DEST_DIR:-$HOME/Library/Screen Savers}"
DEST="$DEST_DIR/Ame.saver"

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR
fi

xcodebuild \
    -project "$ROOT_DIR/ame.xcodeproj" \
    -scheme AmeScreenSaver \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$PRODUCT" "$DEST"

echo "Installed $DEST"
echo "Select Ame in System Settings > Screen Saver once. Then run: ame"

if [[ "${AME_OPEN_SETTINGS:-1}" == "1" ]]; then
  open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension" || open -b com.apple.systempreferences
fi
