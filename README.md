# ClipDisplay

A lightweight native macOS menu-bar app that displays your clipboard text in a fully-styleable, always-on-top floating overlay. Built as a replacement for the "Hotkey" app, adding the font/color/size/position controls it lacks.

- **Native Swift + AppKit** (SwiftUI for the settings form) — no Electron, ~0% idle CPU
- **Agent app** — no Dock icon, just a menu-bar clipboard icon
- Overlay floats above all windows, all Spaces, and full-screen apps
- Drag the overlay anywhere; position and all styling persist across launches

## Hotkeys (global, no Accessibility permission needed)

| Hotkey | Action |
|---|---|
| `⌘⇧V` | Read clipboard → show styled overlay |
| `⌘⇧H` | Toggle overlay visibility |

## Settings

Open **Settings…** from the menu-bar icon. All changes apply to the overlay live: font family, size, bold, text color, background color + opacity, alignment, padding, overlay width/height, and a reset-position button.

## Build & run

Requires macOS 14+ (Apple Silicon) and the Xcode Command Line Tools — full Xcode is not needed.

```sh
./build-app.sh        # builds release binary + assembles ClipDisplay.app (ad-hoc signed)
open ClipDisplay.app  # or drop it in /Applications
```

During development:

```sh
swift run
```

See [SPEC.md](SPEC.md) for the full build spec.
