import AppKit
import SwiftUI

enum TextAlignmentSetting: Int, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

/// UserDefaults-backed settings model shared by the SwiftUI form and the overlay panel.
/// Every mutation saves immediately and notifies `onChange` so the overlay updates live.
final class SettingsModel: ObservableObject {
    var onChange: (() -> Void)?
    var onResetPosition: (() -> Void)?
    var onHotKeysChange: (() -> Void)?

    @Published var fontFamily: String = Defaults.fontFamily { didSet { changed() } }
    @Published var fontSize: Double = Defaults.fontSize { didSet { changed() } }
    @Published var bold: Bool = Defaults.bold { didSet { changed() } }
    @Published var textColor: NSColor = Defaults.textColor { didSet { changed() } }
    @Published var backgroundColor: NSColor = Defaults.backgroundColor { didSet { changed() } }
    @Published var backgroundOpacity: Double = Defaults.backgroundOpacity { didSet { changed() } }
    @Published var alignment: TextAlignmentSetting = Defaults.alignment { didSet { changed() } }
    @Published var padding: Double = Defaults.padding { didSet { changed() } }
    @Published var overlayWidth: Double = Defaults.overlayWidth { didSet { changed() } }
    @Published var overlayHeight: Double = Defaults.overlayHeight { didSet { changed() } }
    @Published var showClipboardHotKey: HotKeyCombo = .defaultShowClipboard { didSet { hotKeysChanged() } }
    @Published var toggleOverlayHotKey: HotKeyCombo = .defaultToggleOverlay { didSet { hotKeysChanged() } }

    enum Defaults {
        static let fontFamily = "Helvetica Neue"
        static let fontSize: Double = 48
        static let bold = false
        static let textColor: NSColor = .white
        static let backgroundColor: NSColor = .black
        static let backgroundOpacity: Double = 0.85
        static let alignment: TextAlignmentSetting = .center
        static let padding: Double = 24
        static let overlayWidth: Double = 800
        static let overlayHeight: Double = 300
    }

    private enum Key {
        static let fontFamily = "fontFamily"
        static let fontSize = "fontSize"
        static let bold = "bold"
        static let textColor = "textColor"
        static let backgroundColor = "backgroundColor"
        static let backgroundOpacity = "backgroundOpacity"
        static let alignment = "alignment"
        static let padding = "padding"
        static let overlayWidth = "overlayWidth"
        static let overlayHeight = "overlayHeight"
        static let hasOrigin = "panelHasOrigin"
        static let originX = "panelOriginX"
        static let originY = "panelOriginY"
        static let showHotKeyCode = "showHotKeyCode"
        static let showHotKeyModifiers = "showHotKeyModifiers"
        static let toggleHotKeyCode = "toggleHotKeyCode"
        static let toggleHotKeyModifiers = "toggleHotKeyModifiers"
    }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    init() {
        load()
        isLoading = false
    }

    private func changed() {
        guard !isLoading else { return }
        save()
        onChange?()
    }

    private func hotKeysChanged() {
        guard !isLoading else { return }
        save()
        onHotKeysChange?()
    }

    func resetHotKeys() {
        showClipboardHotKey = .defaultShowClipboard
        toggleOverlayHotKey = .defaultToggleOverlay
    }

    // MARK: - Persistence

    private func load() {
        let d = defaults
        if let family = d.string(forKey: Key.fontFamily) { fontFamily = family }
        if d.object(forKey: Key.fontSize) != nil { fontSize = d.double(forKey: Key.fontSize) }
        if d.object(forKey: Key.bold) != nil { bold = d.bool(forKey: Key.bold) }
        if let color = Self.color(from: d.data(forKey: Key.textColor)) { textColor = color }
        if let color = Self.color(from: d.data(forKey: Key.backgroundColor)) { backgroundColor = color }
        if d.object(forKey: Key.backgroundOpacity) != nil { backgroundOpacity = d.double(forKey: Key.backgroundOpacity) }
        if let raw = d.object(forKey: Key.alignment) as? Int, let a = TextAlignmentSetting(rawValue: raw) { alignment = a }
        if d.object(forKey: Key.padding) != nil { padding = d.double(forKey: Key.padding) }
        if d.object(forKey: Key.overlayWidth) != nil { overlayWidth = d.double(forKey: Key.overlayWidth) }
        if d.object(forKey: Key.overlayHeight) != nil { overlayHeight = d.double(forKey: Key.overlayHeight) }
        if d.object(forKey: Key.showHotKeyCode) != nil {
            showClipboardHotKey = HotKeyCombo(keyCode: UInt32(d.integer(forKey: Key.showHotKeyCode)),
                                              modifiers: UInt32(d.integer(forKey: Key.showHotKeyModifiers)))
        }
        if d.object(forKey: Key.toggleHotKeyCode) != nil {
            toggleOverlayHotKey = HotKeyCombo(keyCode: UInt32(d.integer(forKey: Key.toggleHotKeyCode)),
                                              modifiers: UInt32(d.integer(forKey: Key.toggleHotKeyModifiers)))
        }
    }

    private func save() {
        let d = defaults
        d.set(fontFamily, forKey: Key.fontFamily)
        d.set(fontSize, forKey: Key.fontSize)
        d.set(bold, forKey: Key.bold)
        d.set(Self.data(from: textColor), forKey: Key.textColor)
        d.set(Self.data(from: backgroundColor), forKey: Key.backgroundColor)
        d.set(backgroundOpacity, forKey: Key.backgroundOpacity)
        d.set(alignment.rawValue, forKey: Key.alignment)
        d.set(padding, forKey: Key.padding)
        d.set(overlayWidth, forKey: Key.overlayWidth)
        d.set(overlayHeight, forKey: Key.overlayHeight)
        d.set(Int(showClipboardHotKey.keyCode), forKey: Key.showHotKeyCode)
        d.set(Int(showClipboardHotKey.modifiers), forKey: Key.showHotKeyModifiers)
        d.set(Int(toggleOverlayHotKey.keyCode), forKey: Key.toggleHotKeyCode)
        d.set(Int(toggleOverlayHotKey.modifiers), forKey: Key.toggleHotKeyModifiers)
    }

    // MARK: - Panel position

    func saveOrigin(_ origin: NSPoint) {
        defaults.set(true, forKey: Key.hasOrigin)
        defaults.set(Double(origin.x), forKey: Key.originX)
        defaults.set(Double(origin.y), forKey: Key.originY)
    }

    func savedOrigin() -> NSPoint? {
        guard defaults.bool(forKey: Key.hasOrigin) else { return nil }
        return NSPoint(x: defaults.double(forKey: Key.originX),
                       y: defaults.double(forKey: Key.originY))
    }

    func resetPosition() {
        defaults.removeObject(forKey: Key.hasOrigin)
        defaults.removeObject(forKey: Key.originX)
        defaults.removeObject(forKey: Key.originY)
        onResetPosition?()
    }

    // MARK: - Color round-tripping (archived NSColor keeps exact color space + components)

    private static func data(from color: NSColor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }

    private static func color(from data: Data?) -> NSColor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
}
