import AppKit
import Carbon.HIToolbox

/// A user-bindable key combination: a virtual key code plus a Carbon modifier mask.
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon mask: cmdKey / optionKey / controlKey / shiftKey

    static let defaultShowClipboard = HotKeyCombo(keyCode: UInt32(kVK_Space),
                                                  modifiers: UInt32(optionKey | shiftKey))
    static let defaultToggleOverlay = HotKeyCombo(keyCode: UInt32(kVK_ANSI_H),
                                                  modifiers: UInt32(cmdKey | shiftKey))

    /// Global hotkeys must include ⌘, ⌥, or ⌃ — shift alone would swallow normal typing.
    var hasActionModifier: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    // MARK: - Display

    var displayString: String {
        var glyphs = ""
        if modifiers & UInt32(controlKey) != 0 { glyphs += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { glyphs += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { glyphs += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { glyphs += "⌘" }
        return glyphs + keyName
    }

    var keyName: String {
        if let special = Self.specialKeyNames[keyCode] { return special }
        if let character = Self.baseCharacter(for: keyCode) { return character.uppercased() }
        return "Key \(keyCode)"
    }

    /// Character usable as an NSMenuItem key equivalent, or nil for
    /// non-character keys (arrows, F-keys, …).
    var keyEquivalentCharacter: String? {
        if keyCode == UInt32(kVK_Space) { return " " }
        if Self.specialKeyNames[keyCode] != nil { return nil }
        return Self.baseCharacter(for: keyCode)?.lowercased()
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    /// Unmodified character for a key code, via the current keyboard layout.
    private static func baseCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self) as Data

        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout,
                                        UInt16(keyCode),
                                        UInt16(kUCKeyActionDisplay),
                                        0, // no modifiers — base character
                                        UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeyState,
                                        chars.count,
                                        &length,
                                        &chars)
            guard status == noErr, length > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: length)
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
        }
    }
}

extension Notification.Name {
    /// Posted with userInfo ["recording": Bool] while a settings recorder is
    /// capturing keys, so global hotkeys can be suspended and re-recorded.
    static let hotKeyRecordingChanged = Notification.Name("hotKeyRecordingChanged")
}

/// Global hotkeys via the Carbon RegisterEventHotKey API.
/// Works system-wide without Accessibility permission.
final class HotKeys {
    typealias Handler = () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x434C_4450 // 'CLDP'

    @discardableResult
    func register(_ combo: HotKeyCombo, handler: @escaping Handler) -> Bool {
        if eventHandlerRef == nil { installEventHandler() }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("HotKeys: failed to register \(combo.displayString) (status \(status))")
            return false
        }
        handlers[id] = handler
        hotKeyRefs.append(ref)
        return true
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            hotKeys.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    deinit {
        unregisterAll()
    }
}
