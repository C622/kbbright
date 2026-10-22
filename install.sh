#!/bin/zsh
# Builds kbbright and installs it as a LaunchAgent that starts at login.
set -e
cd "$(dirname "$0")"
DEST="$HOME/Library/Application Support/kbbright"
PLIST="$HOME/Library/LaunchAgents/local.kbbright.plist"
mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
clang -O2 -fobjc-arc -framework AppKit -framework Carbon kbbright.m -o "$DEST/kbbright"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.kbbright</string>
  <key>ProgramArguments</key><array><string>$DEST/kbbright</string><string>daemon</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/kbbright.log</string>
</dict></plist>
PL
launchctl bootout gui/$(id -u)/local.kbbright 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "kbbright installed and running."
