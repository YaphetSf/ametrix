#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
PRODUCT="$DERIVED_DATA/Build/Products/Release/Ametrix.saver"
DEST_DIR="${AMETRIX_SAVER_DEST_DIR:-$HOME/Library/Screen Savers}"
DEST="$DEST_DIR/Ametrix.saver"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -n "${DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR
fi

xcodebuild \
    -project "$ROOT_DIR/ametrix.xcodeproj" \
    -scheme AmetrixScreenSaver \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$PRODUCT" "$DEST"

echo "Installed $DEST"
echo "Select Ametrix in System Settings > Screen Saver once. Then run: ametrix"

if [[ "${AMETRIX_OPEN_SETTINGS:-1}" == "1" ]]; then
  open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension" || open -b com.apple.systempreferences
fi
