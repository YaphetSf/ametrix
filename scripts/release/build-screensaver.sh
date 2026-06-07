#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
PRODUCT="$DERIVED_DATA/Build/Products/Release/Ametrix.saver"
DEST_DIR="${AMETRIX_SAVER_DEST_DIR:-$ROOT_DIR/dist}"
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

echo "Built $DEST"
