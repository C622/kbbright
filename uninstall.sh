#!/bin/zsh
launchctl bootout gui/$(id -u)/local.kbbright 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.kbbright.plist"
rm -rf "$HOME/Library/Application Support/kbbright"
echo "kbbright removed."
