import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsModel()
    private let hotKeys = HotKeys()
    private var overlay: OverlayPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var showClipboardItem: NSMenuItem?
    private var showHideItem: NSMenuItem?

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
        settings.onHotKeysChange = { [weak self] in
            self?.registerHotKeys()
        }

        // Suspend global hotkeys while a settings recorder is capturing keys,
        // so the currently bound combo can itself be re-recorded.
        NotificationCenter.default.addObserver(forName: .hotKeyRecordingChanged,
                                               object: nil,
                                               queue: .main) { [weak self] note in
            guard let self else { return }
            if note.userInfo?["recording"] as? Bool == true {
                self.hotKeys.unregisterAll()
            } else {
                self.registerHotKeys()
            }
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

        let showClip = NSMenuItem(title: "Show Clipboard",
                                  action: #selector(showClipboard),
                                  keyEquivalent: "")
        showClip.target = self
        menu.addItem(showClip)
        showClipboardItem = showClip

        let showHide = NSMenuItem(title: "Show/Hide Overlay",
                                  action: #selector(toggleOverlay),
                                  keyEquivalent: "")
        showHide.target = self
        menu.addItem(showHide)
        showHideItem = showHide

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
        hotKeys.unregisterAll()
        // Default ⌥⇧Space — read clipboard, update overlay, show it
        hotKeys.register(settings.showClipboardHotKey) { [weak self] in
            self?.showClipboard()
        }
        // Default ⌘⇧H — toggle overlay visibility
        hotKeys.register(settings.toggleOverlayHotKey) { [weak self] in
            self?.toggleOverlay()
        }
        updateMenuKeyEquivalents()
    }

    private func updateMenuKeyEquivalents() {
        applyKeyEquivalent(settings.showClipboardHotKey, to: showClipboardItem)
        applyKeyEquivalent(settings.toggleOverlayHotKey, to: showHideItem)
    }

    private func applyKeyEquivalent(_ combo: HotKeyCombo, to item: NSMenuItem?) {
        item?.keyEquivalent = combo.keyEquivalentCharacter ?? ""
        item?.keyEquivalentModifierMask = combo.cocoaModifiers
    }

    // MARK: - Actions

    @objc private func showClipboard() {
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
