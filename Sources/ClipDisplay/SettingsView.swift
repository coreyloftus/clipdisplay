import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    private let fontFamilies = NSFontManager.shared.availableFontFamilies

    private var maxWidth: Double { Double(NSScreen.main?.frame.width ?? 3840) }
    private var maxHeight: Double { Double(NSScreen.main?.frame.height ?? 2160) }

    private var textColor: Binding<Color> {
        Binding(get: { Color(nsColor: settings.textColor) },
                set: { settings.textColor = NSColor($0) })
    }

    private var backgroundColor: Binding<Color> {
        Binding(get: { Color(nsColor: settings.backgroundColor) },
                set: { settings.backgroundColor = NSColor($0) })
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

                ColorPicker("Text color", selection: textColor)

                Picker("Alignment", selection: $settings.alignment) {
                    ForEach(TextAlignmentSetting.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Background") {
                ColorPicker("Background color", selection: backgroundColor)

                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $settings.backgroundOpacity, in: 0...1)
                        Text("\(Int(settings.backgroundOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section("Layout") {
                LabeledContent("Padding") {
                    HStack {
                        Slider(value: $settings.padding, in: 0...120)
                        Text("\(Int(settings.padding)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                LabeledContent("Overlay width") {
                    HStack {
                        TextField("Width", value: $settings.overlayWidth, format: .number.precision(.fractionLength(0)))
                            .labelsHidden()
                            .frame(width: 64)
                        Stepper("Width", value: $settings.overlayWidth, in: 100...maxWidth, step: 10)
                            .labelsHidden()
                    }
                }

                LabeledContent("Overlay height") {
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
            }

            Section {
                LabeledContent("Show clipboard", value: "⌘⇧V")
                LabeledContent("Toggle overlay", value: "⌘⇧H")
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Changes apply to the overlay immediately.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 520)
    }
}
