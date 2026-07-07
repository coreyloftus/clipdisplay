import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    private let fontFamilies = NSFontManager.shared.availableFontFamilies

    private var maxWidth: Double { Double(NSScreen.main?.frame.width ?? 3840) }
    private var maxHeight: Double { Double(NSScreen.main?.frame.height ?? 2160) }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SettingsModel, NSColor>) -> Binding<Color> {
        Binding(get: { Color(nsColor: settings[keyPath: keyPath]) },
                set: { settings[keyPath: keyPath] = NSColor($0) })
    }

    var body: some View {
        Form {
            Section("Text") {
                Picker("Font family", selection: $settings.fontFamily) {
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $settings.fontSize, in: 12...300)
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Toggle("Bold", isOn: $settings.bold)

                Picker("Alignment", selection: $settings.alignment) {
                    ForEach(TextAlignmentSetting.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Follow system light/dark mode", isOn: $settings.followSystemAppearance)

                if settings.followSystemAppearance {
                    ColorPicker("Light mode — text", selection: colorBinding(\.lightTextColor))
                    ColorPicker("Light mode — background", selection: colorBinding(\.lightBackgroundColor))
                    ColorPicker("Dark mode — text", selection: colorBinding(\.darkTextColor))
                    ColorPicker("Dark mode — background", selection: colorBinding(\.darkBackgroundColor))
                } else {
                    ColorPicker("Text color", selection: colorBinding(\.textColor))
                    ColorPicker("Background color", selection: colorBinding(\.backgroundColor))
                }

                LabeledContent("Background opacity") {
                    HStack {
                        Slider(value: $settings.backgroundOpacity, in: 0...1)
                        Text("\(Int(settings.backgroundOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } header: {
                Text("Colors")
            } footer: {
                Text(settings.followSystemAppearance
                     ? "The overlay switches color sets automatically when macOS changes appearance."
                     : "One fixed color set is used regardless of the system appearance.")
            }

            Section {
                Toggle("Auto-size overlay to content", isOn: $settings.autoSizeOverlay)
                Toggle("Shrink text to fit", isOn: $settings.shrinkTextToFit)
                Toggle("Scroll overflowing content", isOn: $settings.scrollOverflow)

                LabeledContent("Padding") {
                    HStack {
                        Slider(value: $settings.padding, in: 0...120)
                        Text("\(Int(settings.padding)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                LabeledContent(settings.autoSizeOverlay ? "Max width" : "Overlay width") {
                    HStack {
                        TextField("Width", value: $settings.overlayWidth, format: .number.precision(.fractionLength(0)))
                            .labelsHidden()
                            .frame(width: 64)
                        Stepper("Width", value: $settings.overlayWidth, in: 100...maxWidth, step: 10)
                            .labelsHidden()
                    }
                }

                LabeledContent(settings.autoSizeOverlay ? "Max height" : "Overlay height") {
                    HStack {
                        TextField("Height", value: $settings.overlayHeight, format: .number.precision(.fractionLength(0)))
                            .labelsHidden()
                            .frame(width: 64)
                        Stepper("Height", value: $settings.overlayHeight, in: 60...maxHeight, step: 10)
                            .labelsHidden()
                    }
                }

                Button("Reset Position") {
                    settings.resetPosition()
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Auto-size hugs the content and treats width/height as maximums. When content overflows, text shrinks to 10 pt before scrolling kicks in.")
            }

            Section {
                HotKeyRecorderRow(title: "Show clipboard",
                                  combo: $settings.showClipboardHotKey,
                                  conflictingCombo: settings.toggleOverlayHotKey)
                HotKeyRecorderRow(title: "Toggle overlay",
                                  combo: $settings.toggleOverlayHotKey,
                                  conflictingCombo: settings.showClipboardHotKey)
                Button("Reset Hotkeys to Defaults") {
                    settings.resetHotKeys()
                }
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Click a shortcut, then press a new key combination including ⌘, ⌥, or ⌃. Press ⎋ to cancel. Changes apply immediately.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 560)
    }
}

/// Click-to-record shortcut field. While recording, global hotkeys are
/// suspended (via .hotKeyRecordingChanged) so the current binding can be
/// captured and re-assigned.
struct HotKeyRecorderRow: View {
    let title: String
    @Binding var combo: HotKeyCombo
    let conflictingCombo: HotKeyCombo

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    var body: some View {
        LabeledContent(title) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press shortcut…" : combo.displayString)
                    .frame(minWidth: 110)
            }
            .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        postRecordingState(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow the keystroke
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode),
                                    modifiers: HotKeyCombo.carbonModifiers(from: event.modifierFlags))
        guard candidate.hasActionModifier, candidate != conflictingCombo else {
            NSSound.beep()
            return
        }
        combo = candidate
        stopRecording()
    }

    private func stopRecording() {
        guard isRecording || keyMonitor != nil else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecording = false
        postRecordingState(false)
    }

    private func postRecordingState(_ recording: Bool) {
        NotificationCenter.default.post(name: .hotKeyRecordingChanged,
                                        object: nil,
                                        userInfo: ["recording": recording])
    }
}
