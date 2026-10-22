# kbbright

Keyboard backlight shortcuts for Apple Silicon MacBooks.

Since the M1 generation, MacBook keyboards no longer have backlight keys, and
macOS has no built-in shortcut for keyboard brightness. kbbright adds one:

| Shortcut | Action |
|---|---|
| **Shift** or **Option** + Brightness Down | Keyboard backlight down |
| **Shift** or **Option** + Brightness Up | Keyboard backlight up |

"Brightness Down/Up" are the screen-brightness keys: F1/F2 on the built-in
keyboard, or F13/F14 (or whatever sends brightness) on an external keyboard.
Without a modifier they still change screen brightness as normal. Each press moves
the backlight 1/16, the same step size the old hardware keys used.

## Install

You need the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/C622/kbbright.git
cd kbbright
./install.sh
```

This builds the tool, copies it to `~/Library/Application Support/kbbright/`,
and adds a login item (`~/Library/LaunchAgents/local.kbbright.plist`) so it
starts automatically.

Then grant it **Accessibility** permission: open System Settings → Privacy &
Security → Accessibility, click **+**, press Cmd+Shift+G and add
`~/Library/Application Support/kbbright/kbbright`. It starts working within a
couple of seconds; no restart needed. If you re-run `install.sh` later, macOS may
ask you to grant the permission again.

## Command line

```bash
~/Library/Application\ Support/kbbright/kbbright get        # 0.0–1.0
~/Library/Application\ Support/kbbright/kbbright set 0.5
~/Library/Application\ Support/kbbright/kbbright up
~/Library/Application\ Support/kbbright/kbbright down
```

## Uninstall

```bash
./uninstall.sh
```

Then remove the entry from the Accessibility list.

## How it works

- The backlight is set through `KeyboardBrightnessClient` in Apple's private
  CoreBrightness framework, which is what Control Center's keyboard brightness
  slider uses. Being a private API, a future macOS update could break it.
- The shortcuts use a `CGEventTap`. It catches the screen-brightness key events
  (and F13/F14) and swallows them when Shift or Option is held, so the display
  brightness doesn't change. That's why Accessibility permission is needed.
- If the backlight changes by itself, turn off "Adjust keyboard brightness in
  low light" in System Settings → Keyboard.

## Troubleshooting

Logs go to `~/Library/Logs/kbbright.log`. To log every brightness key event,
add `KBBRIGHT_DEBUG=1` to the LaunchAgent's environment, or stop the agent and
run it by hand:

```bash
launchctl bootout gui/$(id -u)/local.kbbright
KBBRIGHT_DEBUG=1 ~/Library/Application\ Support/kbbright/kbbright daemon
```

Tested on a MacBook Pro M2 with macOS 27.

## License

MIT
