#!/usr/bin/env bash
set -euo pipefail

LABEL="com.dingz.uk.ametrix.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
WALLPAPER_LABEL="com.dingz.uk.ametrix.wallpaper"
WALLPAPER_PLIST_PATH="$HOME/Library/LaunchAgents/$WALLPAPER_LABEL.plist"
OLD_MENUBAR_LABEL="org.ame.menubar"
OLD_MENUBAR_PLIST_PATH="$HOME/Library/LaunchAgents/$OLD_MENUBAR_LABEL.plist"
OLD_WALLPAPER_LABEL="org.ame.wallpaper"
OLD_WALLPAPER_PLIST_PATH="$HOME/Library/LaunchAgents/$OLD_WALLPAPER_LABEL.plist"

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "--remove" ]]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "Removed $PLIST_PATH"
  exit 0
fi

if [[ -n "${AMETRIX_BIN_DEST:-}" ]]; then
  AMETRIX_PATH="$AMETRIX_BIN_DEST"
elif command -v ametrix >/dev/null 2>&1; then
  AMETRIX_PATH="$(command -v ametrix)"
elif command -v brew >/dev/null 2>&1 && [[ -x "$(brew --prefix)/bin/ametrix" ]]; then
  AMETRIX_PATH="$(brew --prefix)/bin/ametrix"
elif [[ -x "$HOME/.local/bin/ametrix" ]]; then
  AMETRIX_PATH="$HOME/.local/bin/ametrix"
else
  echo "Error: ametrix binary not found."
  echo "Run scripts/install.sh first, or set AMETRIX_BIN_DEST to the installed ametrix path."
  exit 1
fi

if [[ ! -x "$AMETRIX_PATH" ]]; then
  echo "Error: ametrix is not executable at $AMETRIX_PATH"
  exit 1
fi

if ! "$AMETRIX_PATH" --help 2>/dev/null | grep -q -- "--menubar"; then
  echo "Error: $AMETRIX_PATH does not support --menubar."
  echo "Run scripts/install.sh first, or set AMETRIX_BIN_DEST to a freshly built ametrix binary."
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

START_WALLPAPER="${AMETRIX_MENUBAR_START_WALLPAPER:-0}"
if [[ "$START_WALLPAPER" != "1" && ( -f "$WALLPAPER_PLIST_PATH" || -f "$OLD_WALLPAPER_PLIST_PATH" ) ]]; then
  START_WALLPAPER=1
fi
START_WALLPAPER_ARG=""
if [[ "$START_WALLPAPER" == "1" ]]; then
  START_WALLPAPER_ARG=$'\n\t\t<string>--wallpaper</string>'
fi

launchctl unload "$WALLPAPER_PLIST_PATH" 2>/dev/null || true
rm -f "$WALLPAPER_PLIST_PATH"
launchctl unload "$OLD_MENUBAR_PLIST_PATH" 2>/dev/null || true
rm -f "$OLD_MENUBAR_PLIST_PATH"
launchctl unload "$OLD_WALLPAPER_PLIST_PATH" 2>/dev/null || true
rm -f "$OLD_WALLPAPER_PLIST_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$AMETRIX_PATH</string>
		<string>--menubar</string>$START_WALLPAPER_ARG
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>StandardOutPath</key>
	<string>/tmp/ametrix-menubar.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/ametrix-menubar.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f /tmp/ametrix-menubar.log
launchctl load "$PLIST_PATH"

echo "Installed and started $PLIST_PATH"
echo "Menu bar log: /tmp/ametrix-menubar.log"
echo "Removed old Ametrix/Ame menu bar and standalone wallpaper agents if they existed."
if [[ "$START_WALLPAPER" == "1" ]]; then
  echo "Wallpaper starts enabled in menu bar mode."
fi
echo "Remove it with: scripts/install-menubar-agent.sh --uninstall"
