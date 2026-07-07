import Carbon.HIToolbox
import Foundation

/// Global hotkeys via the Carbon RegisterEventHotKey API.
/// Works system-wide without Accessibility permission.
final class HotKeys {
    typealias Handler = () -> Void

    static let cmdShift = UInt32(cmdKey | shiftKey)

    private var handlers: [UInt32: Handler] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x434C_4450 // 'CLDP'

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) -> Bool {
        if eventHandlerRef == nil { installEventHandler() }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("HotKeys: failed to register keyCode \(keyCode) (status \(status))")
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
