#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${AME_BIN_DEST:-}" ]]; then
  BIN_DEST="$AME_BIN_DEST"
elif command -v brew >/dev/null 2>&1; then
  BIN_DEST="$(brew --prefix)/bin/ame"
else
  BIN_DEST="$HOME/.local/bin/ame"
fi

cd "$ROOT_DIR"

swift build --disable-sandbox -c release
mkdir -p "$(dirname "$BIN_DEST")"
cp "$ROOT_DIR/.build/release/ame" "$BIN_DEST"

"$ROOT_DIR/scripts/install-config.sh"
AME_OPEN_SETTINGS="${AME_OPEN_SETTINGS:-0}" "$ROOT_DIR/scripts/install-screensaver.sh"

echo "Installed CLI to $BIN_DEST"
echo "Run: ame"
