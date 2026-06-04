#!/usr/bin/env bash
set -euo pipefail

LABEL="org.ame.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
WALLPAPER_LABEL="org.ame.wallpaper"
WALLPAPER_PLIST_PATH="$HOME/Library/LaunchAgents/$WALLPAPER_LABEL.plist"

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "--remove" ]]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "Removed $PLIST_PATH"
  exit 0
fi

if [[ -n "${AME_BIN_DEST:-}" ]]; then
  AME_PATH="$AME_BIN_DEST"
elif command -v ame >/dev/null 2>&1; then
  AME_PATH="$(command -v ame)"
elif command -v brew >/dev/null 2>&1 && [[ -x "$(brew --prefix)/bin/ame" ]]; then
  AME_PATH="$(brew --prefix)/bin/ame"
elif [[ -x "$HOME/.local/bin/ame" ]]; then
  AME_PATH="$HOME/.local/bin/ame"
else
  echo "Error: ame binary not found."
  echo "Run scripts/install.sh first, or set AME_BIN_DEST to the installed ame path."
  exit 1
fi

if [[ ! -x "$AME_PATH" ]]; then
  echo "Error: ame is not executable at $AME_PATH"
  exit 1
fi

if ! "$AME_PATH" --help 2>/dev/null | grep -q -- "--menubar"; then
  echo "Error: $AME_PATH does not support --menubar."
  echo "Run scripts/install.sh first, or set AME_BIN_DEST to a freshly built ame binary."
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

START_WALLPAPER="${AME_MENUBAR_START_WALLPAPER:-0}"
if [[ "$START_WALLPAPER" != "1" && -f "$WALLPAPER_PLIST_PATH" ]]; then
  START_WALLPAPER=1
fi
START_WALLPAPER_ARG=""
if [[ "$START_WALLPAPER" == "1" ]]; then
  START_WALLPAPER_ARG=$'\n\t\t<string>--wallpaper</string>'
fi

launchctl unload "$WALLPAPER_PLIST_PATH" 2>/dev/null || true
rm -f "$WALLPAPER_PLIST_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$AME_PATH</string>
		<string>--menubar</string>$START_WALLPAPER_ARG
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>StandardOutPath</key>
	<string>/tmp/ame-menubar.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/ame-menubar.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f /tmp/ame-menubar.log
launchctl load "$PLIST_PATH"

echo "Installed and started $PLIST_PATH"
echo "Menu bar log: /tmp/ame-menubar.log"
echo "Removed standalone wallpaper agent if it existed: $WALLPAPER_PLIST_PATH"
if [[ "$START_WALLPAPER" == "1" ]]; then
  echo "Wallpaper starts enabled in menu bar mode."
fi
echo "Remove it with: scripts/install-menubar-agent.sh --uninstall"
