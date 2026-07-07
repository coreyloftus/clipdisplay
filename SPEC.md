# ClipDisplay — Build Spec

A lightweight native macOS app that displays clipboard contents in a fully-styleable, always-on-top floating overlay. It is a replacement for the "Hotkey" app, adding the font/color/size/position controls that Hotkey lacks.

**Target platform:** macOS (Apple Silicon, macOS 14+).
**Stack:** Native Swift + AppKit + SwiftUI (settings UI only). No Electron, no bundled runtime.
**Toolchain constraint:** Build with **Swift Package Manager + `swiftc`** only. Command-line tools are installed, but **full Xcode is NOT available** — do not use `xcodebuild` or `.xcodeproj`. Assemble the `.app` bundle manually via a shell script.

---

## 1. Goals & non-goals

### Goals
- Show the current clipboard **text** in a floating overlay on a global hotkey press.
- Give the user full control over how that text looks and where it sits on screen.
- Run as lightly as possible: agent app, no Dock icon, ~0% idle CPU, minimal RAM.

### Non-goals (v1)
- Displaying clipboard **images** (show a placeholder note instead; leave a clean seam to add later).
- Rebindable hotkeys via UI (hotkeys are hardcoded in v1).
- Clipboard history / multiple clips.
- Windows/Linux support.

---

## 2. App shape

- **Agent app**: set `LSUIElement` = `true` in `Info.plist`. No Dock icon, no main menu bar app menu.
- **Menu-bar status item** (`NSStatusItem`) is the only persistent UI. Its dropdown menu:
  - `Show/Hide Overlay`
  - `Settings…`
  - `Quit`
- Launches instantly and sits idle waiting for hotkeys.

---

## 3. The overlay panel

- A borderless **`NSPanel`** (subclass or configured instance) with:
  - Style mask: `.borderless`, `.nonactivatingPanel`.
  - `isFloatingPanel = true`, `level = .floating` (or `.statusBar` if it must sit above more) so it stays above normal windows.
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` so it appears on all Spaces and over full-screen apps.
  - `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`.
  - Background: honor the user's background color + opacity. When opacity is 0, the panel window is effectively transparent (`isOpaque = false`, `backgroundColor = .clear`, content view draws the styled background).
- **Content:** the clipboard text, rendered with the user's font/size/weight/color/alignment/padding. Use an `NSTextField` (multiline, wrapping) or `NSTextView`, or an `NSHostingView` wrapping a SwiftUI `Text` — implementer's choice; must support multi-line wrapping and the styling controls below.
- **Positioning & sizing:**
  - Position and size come from Settings (persisted).
  - **Drag-to-move** is enabled (`isMovableByWindowBackground`); the moved frame origin is persisted so it reopens where the user left it.
  - Width/height are set from Settings steppers; the panel resizes to match.
- **Empty / non-text clipboard:** if the clipboard has no string, display a subtle placeholder like `— no text on clipboard —` using the same styling.

---

## 4. Global hotkeys

Use the **Carbon `RegisterEventHotKey` API** (via `Carbon.HIToolbox`). This works globally **without** requiring Accessibility permission — do not use an `NSEvent` global monitor (that needs Accessibility and is worse UX).

- `⌘⇧V` (Cmd+Shift+V): read clipboard → update overlay text → show & order-front the panel.
- `⌘⇧H` (Cmd+Shift+H): toggle overlay visibility.

Hotkeys register at launch and unregister on quit. Keep the registration in a dedicated `HotKeys` module with a callback closure interface.

---

## 5. Reading the clipboard

- `NSPasteboard.general.string(forType: .string)`.
- Read fresh on each `⌘⇧V` press (do not poll continuously).

---

## 6. Settings

A SwiftUI form presented in a normal titled `NSWindow` (opened from the menu bar `Settings…` item). Changes apply **live** to the overlay as they are edited.

| Setting | Type | Range / options | Default |
|---|---|---|---|
| Font family | picker of available system font family names | `NSFontManager.shared.availableFontFamilies` | `Helvetica Neue` |
| Font size | slider | 12 – 300 pt | 48 |
| Bold | toggle | — | off |
| Text color | color picker | any | white (`#FFFFFF`) |
| Background color | color picker | any | black (`#000000`) |
| Background opacity | slider | 0 – 100% | 85% |
| Text alignment | segmented | left / center / right | center |
| Padding | slider | 0 – 120 pt | 24 |
| Overlay width | stepper / field | 100 – screen width | 800 |
| Overlay height | stepper / field | 60 – screen height | 300 |
| Reset position | button | recenters panel on main screen | — |

Use SwiftUI `ColorPicker`, `Slider`, `Picker`, `Stepper`, `Toggle`.

---

## 7. Persistence

- Store all settings in **`UserDefaults`** (standard suite). No files to manage.
- Persist: every setting above **plus** the panel frame origin (x, y) after drag-to-move.
- Colors: persist as hex strings or archived `NSColor` data — implementer's choice; must round-trip exactly.
- On launch: load settings, apply to overlay, restore panel frame. If no saved position, center on main screen.

---

## 8. Architecture / file layout

```
clipdisplay/
├── Package.swift               # SwiftPM manifest, executable target "ClipDisplay"
├── Sources/ClipDisplay/
│   ├── main.swift              # NSApplication bootstrap, sets delegate, .accessory activation policy
│   ├── AppDelegate.swift       # status item + menu, wires hotkeys → overlay, opens settings
│   ├── OverlayPanel.swift      # borderless floating NSPanel + styled text rendering + apply(settings:)
│   ├── HotKeys.swift           # Carbon RegisterEventHotKey wrapper with callbacks
│   ├── Settings.swift          # UserDefaults-backed model (Codable-ish), load/save, defaults
│   └── SettingsView.swift      # SwiftUI settings form, bound to Settings, live-applies changes
├── Resources/
│   └── Info.plist              # LSUIElement=true, bundle id, name, version
└── build-app.sh               # swift build -c release, then assemble ClipDisplay.app
```

### Wiring notes
- `main.swift`: create `NSApplication`, set `activationPolicy = .accessory`, assign `AppDelegate`, run.
- `AppDelegate`: on `applicationDidFinishLaunching`, build the status item + menu, instantiate `OverlayPanel`, load `Settings`, register hotkeys with closures that call the overlay.
- Settings changes propagate to `OverlayPanel.apply(settings:)`. Use a shared observable settings object (e.g. an `ObservableObject`) so the SwiftUI form and the panel stay in sync; on any change, save to `UserDefaults` and re-apply to the panel.

---

## 9. Build & run

`build-app.sh` should:
1. `swift build -c release`.
2. Create `ClipDisplay.app/Contents/{MacOS,Resources}`.
3. Copy the built binary to `Contents/MacOS/ClipDisplay`.
4. Copy `Info.plist` to `Contents/`.
5. (Optional) ad-hoc codesign: `codesign --force --deep --sign - ClipDisplay.app` so it runs without Gatekeeper nagging on the local machine.

Result: a double-clickable `ClipDisplay.app` the user can drop in `/Applications`. Also runnable directly via `swift run` during development.

**Acceptance:** after launch, menu-bar icon appears; copy some text, press `⌘⇧V`, the styled overlay appears with that text; opening Settings and changing font/size/colors/position updates the overlay live; quitting and relaunching restores all settings and the last overlay position.

---

## 10. Info.plist keys (minimum)

- `CFBundleName` = `ClipDisplay`
- `CFBundleIdentifier` = `com.loftuslogic.clipdisplay`
- `CFBundleVersion` / `CFBundleShortVersionString` = `1.0`
- `CFBundlePackageType` = `APPL`
- `LSUIElement` = `true`
- `LSMinimumSystemVersion` = `14.0`
- `NSHighResolutionCapable` = `true`

---

## 11. Nice-to-haves / v2 (do not build now, but keep seams clean)

- Image clipboard display.
- Rebindable hotkeys via Settings.
- Multiple named style presets.
- Auto-fit font size to panel.
- "Live mode" that auto-mirrors clipboard on every copy.
- Launch-at-login toggle (`SMAppService`).
