#!/usr/bin/env bash
set -euo pipefail

LABEL="org.ame.wallpaper"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

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

if ! "$AME_PATH" --help 2>/dev/null | grep -q -- "--wallpaper"; then
  echo "Error: $AME_PATH does not support --wallpaper."
  echo "Run scripts/install.sh first, or set AME_BIN_DEST to a freshly built ame binary."
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

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
		<string>--wallpaper</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>StandardOutPath</key>
	<string>/tmp/ame-wallpaper.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/ame-wallpaper.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f /tmp/ame-wallpaper.log
launchctl load "$PLIST_PATH"

echo "Installed and started $PLIST_PATH"
echo "Wallpaper log: /tmp/ame-wallpaper.log"
echo "Remove it with: scripts/install-wallpaper-agent.sh --uninstall"
