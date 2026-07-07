import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsModel()
    private let hotKeys = HotKeys()
    private var overlay: OverlayPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayPanel(settings: settings)
        overlay.restorePosition()

        settings.onChange = { [weak self] in
            self?.overlay.apply()
        }
        settings.onResetPosition = { [weak self] in
            guard let self else { return }
            self.overlay.centerOnMainScreen()
            self.settings.saveOrigin(self.overlay.frame.origin)
        }

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                               object: overlay,
                                               queue: .main) { [weak self] _ in
            guard let self else { return }
            self.settings.saveOrigin(self.overlay.frame.origin)
        }

        setUpStatusItem()
        registerHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregisterAll()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "ClipDisplay")

        let menu = NSMenu()

        let showHide = NSMenuItem(title: "Show/Hide Overlay",
                                  action: #selector(toggleOverlay),
                                  keyEquivalent: "h")
        showHide.keyEquivalentModifierMask = [.command, .shift]
        showHide.target = self
        menu.addItem(showHide)

        let openSettings = NSMenuItem(title: "Settings…",
                                      action: #selector(showSettings),
                                      keyEquivalent: ",")
        openSettings.target = self
        menu.addItem(openSettings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ClipDisplay",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        // ⌘⇧V — read clipboard, update overlay, show it
        hotKeys.register(keyCode: UInt32(kVK_ANSI_V), modifiers: HotKeys.cmdShift) { [weak self] in
            self?.showClipboard()
        }
        // ⌘⇧H — toggle overlay visibility
        hotKeys.register(keyCode: UInt32(kVK_ANSI_H), modifiers: HotKeys.cmdShift) { [weak self] in
            self?.toggleOverlay()
        }
    }

    // MARK: - Actions

    private func showClipboard() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            overlay.update(text: text)
        } else if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            // v2 seam: image clipboard support lands here.
            overlay.update(text: nil, placeholder: "— image on clipboard (not supported yet) —")
        } else {
            overlay.update(text: nil)
        }
        overlay.orderFrontRegardless()
    }

    @objc private func toggleOverlay() {
        if overlay.isVisible {
            overlay.orderOut(nil)
        } else {
            overlay.orderFrontRegardless()
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "ClipDisplay Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
