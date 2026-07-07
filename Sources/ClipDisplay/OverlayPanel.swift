import AppKit

/// Borderless, non-activating floating panel that renders the clipboard text
/// with the user's styling. Visible on all Spaces and over full-screen apps.
final class OverlayPanel: NSPanel {
    private let settings: SettingsModel
    private let label = NSTextField(wrappingLabelWithString: "")

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!

    private var currentText: String?
    private var placeholderMessage = "— no text on clipboard —"
    private var isShowingPlaceholder: Bool { currentText?.isEmpty ?? true }

    init(settings: SettingsModel) {
        self.settings = settings
        let contentRect = NSRect(x: 0, y: 0,
                                 width: settings.overlayWidth,
                                 height: settings.overlayHeight)
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true
        contentView = content

        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        // The panel's size comes from Settings alone — long clipboard text must
        // wrap and clip inside it, never force the window to grow via Auto Layout.
        label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        label.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        label.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        content.addSubview(label)

        leadingConstraint = label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: settings.padding)
        trailingConstraint = label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -settings.padding)
        topConstraint = label.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: settings.padding)
        bottomConstraint = label.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -settings.padding)
        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            topConstraint,
            bottomConstraint,
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        apply()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Content

    /// Update the displayed text. Pass nil (with an optional placeholder message)
    /// when the clipboard has no string — e.g. empty, or an image (v2 seam).
    func update(text: String?, placeholder: String = "— no text on clipboard —") {
        currentText = text
        placeholderMessage = placeholder
        applySize()
        refreshText()
    }

    /// Re-read all settings and restyle/resize the panel. Called live on every settings change.
    func apply() {
        let content = contentView!

        let opacity = min(max(settings.backgroundOpacity, 0), 1)
        content.layer?.backgroundColor = settings.backgroundColor.withAlphaComponent(opacity).cgColor

        leadingConstraint.constant = settings.padding
        trailingConstraint.constant = -settings.padding
        topConstraint.constant = settings.padding
        bottomConstraint.constant = -settings.padding

        applySize()
        refreshText()
    }

    private func applySize() {
        let size = NSSize(width: max(settings.overlayWidth, 100),
                          height: max(settings.overlayHeight, 60))
        if frame.size != size {
            setContentSize(size)
        }
    }

    private func refreshText() {
        label.preferredMaxLayoutWidth = max(50, frame.width - 2 * settings.padding)
        label.stringValue = isShowingPlaceholder ? placeholderMessage : currentText!
        label.font = resolvedFont()
        label.alignment = settings.alignment.nsAlignment
        label.textColor = isShowingPlaceholder
            ? settings.textColor.withAlphaComponent(0.5)
            : settings.textColor
    }

    private func resolvedFont() -> NSFont {
        let manager = NSFontManager.shared
        let traits: NSFontTraitMask = settings.bold ? .boldFontMask : []
        // Weight 5 is "regular", 9 is "bold" on NSFontManager's 0–15 scale.
        let weight = settings.bold ? 9 : 5
        if let font = manager.font(withFamily: settings.fontFamily,
                                   traits: traits,
                                   weight: weight,
                                   size: settings.fontSize) {
            return font
        }
        return settings.bold
            ? NSFont.boldSystemFont(ofSize: settings.fontSize)
            : NSFont.systemFont(ofSize: settings.fontSize)
    }

    // MARK: - Position

    /// Restore the persisted origin, or center on the main screen.
    /// Falls back to centering if the saved origin is no longer on any screen.
    func restorePosition() {
        if let origin = settings.savedOrigin() {
            let restored = NSRect(origin: origin, size: frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restored) }) {
                setFrameOrigin(origin)
                return
            }
        }
        centerOnMainScreen()
    }

    func centerOnMainScreen() {
        guard let screen = NSScreen.main else {
            center()
            return
        }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - frame.width / 2,
                             y: visible.midY - frame.height / 2)
        setFrameOrigin(origin)
    }
}
