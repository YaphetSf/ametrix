#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY_DIR="${AME_CONFIG_DIR:-$HOME/Library/Application Support/Ame}"
PRIMARY_DEST="$PRIMARY_DIR/config.toml"
LEGACY_DIR="$HOME/.config/ame"
LEGACY_DEST="$LEGACY_DIR/config.toml"
SAVER_CONTAINER_DIR="$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Ame"
SAVER_CONTAINER_DEST="$SAVER_CONTAINER_DIR/config.toml"

mkdir -p "$PRIMARY_DIR"

if [[ -e "$PRIMARY_DEST" ]]; then
  echo "Config already exists: $PRIMARY_DEST"
else
  if [[ -e "$LEGACY_DEST" ]]; then
    cp "$LEGACY_DEST" "$PRIMARY_DEST"
    echo "Installed config to $PRIMARY_DEST from $LEGACY_DEST"
  else
    cp "$ROOT_DIR/config/config.example.toml" "$PRIMARY_DEST"
    echo "Installed config to $PRIMARY_DEST"
  fi
fi

if [[ ! -e "$LEGACY_DEST" ]]; then
  mkdir -p "$LEGACY_DIR"
  cp "$PRIMARY_DEST" "$LEGACY_DEST"
  echo "Installed fallback config to $LEGACY_DEST"
fi

mkdir -p "$SAVER_CONTAINER_DIR"
cp "$PRIMARY_DEST" "$SAVER_CONTAINER_DEST"
echo "Synced screen saver config to $SAVER_CONTAINER_DEST"
