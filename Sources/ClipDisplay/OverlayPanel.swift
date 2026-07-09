import AppKit

/// Text view that lets clicks drag the (isMovableByWindowBackground) panel.
private final class OverlayTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class OverlayScrollView: NSScrollView {
    var scrollingEnabled = true

    override var mouseDownCanMoveWindow: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if scrollingEnabled {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

/// Borderless, non-activating floating panel that renders the clipboard text
/// with the user's styling. Visible on all Spaces and over full-screen apps.
///
/// Sizing: the Settings width/height are treated as a maximum footprint and the
/// min width/height as a floor. With auto-size on, the panel hugs small content
/// (down to the min size); larger content grows the panel to the max, then the
/// font shrinks (down to the settings' min font size), and anything still
/// overflowing scrolls. When "intelligently resize font" is on, the font is
/// fit dynamically to the content length, bounded by the min/max font settings.
final class OverlayPanel: NSPanel {
    private let settings: SettingsModel
    private let scrollView = OverlayScrollView()
    private let textView = OverlayTextView(frame: .zero)

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

        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        leadingConstraint = scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: settings.padding)
        trailingConstraint = scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -settings.padding)
        topConstraint = scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: settings.padding)
        bottomConstraint = scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -settings.padding)
        NSLayoutConstraint.activate([leadingConstraint, trailingConstraint, topConstraint, bottomConstraint])

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
        layoutContent()
    }

    /// Re-read all settings and restyle/resize the panel. Called live on every settings change.
    func apply() {
        let content = contentView!

        let opacity = min(max(settings.backgroundOpacity, 0), 1)
        content.layer?.backgroundColor = settings.effectiveBackgroundColor.withAlphaComponent(opacity).cgColor

        leadingConstraint.constant = settings.padding
        trailingConstraint.constant = -settings.padding
        topConstraint.constant = settings.padding
        bottomConstraint.constant = -settings.padding

        scrollView.scrollingEnabled = settings.scrollOverflow
        scrollView.hasVerticalScroller = settings.scrollOverflow

        layoutContent()
    }

    // MARK: - Adaptive sizing

    private func layoutContent() {
        let pad = max(0, settings.padding)
        // Min width/height are a floor; the settings width/height are the max
        // footprint. Clamp the floor so it can never exceed the max.
        let minW = min(settings.minOverlayWidth, settings.overlayWidth)
        let minH = min(settings.minOverlayHeight, settings.overlayHeight)
        let maxW = max(settings.overlayWidth, minW)
        let maxH = max(settings.overlayHeight, minH)
        let availableWidth = max(50, maxW - 2 * pad)
        let availableHeight = max(30, maxH - 2 * pad)

        let minFont = max(1, min(settings.minFontSize, settings.maxFontSize))
        // Auto-size treats the chosen font size as the natural target and only
        // shrinks it to fit; a fixed-size overlay also grows the text (up to the
        // max font size) to fill the window — so the size tracks text length.
        let maxFont = settings.autoSizeOverlay
            ? max(minFont, settings.fontSize)
            : max(minFont, settings.maxFontSize)

        var fontSize = settings.fontSize
        if settings.shrinkTextToFit {
            if measuredHeight(fontSize: minFont, width: availableWidth) > availableHeight {
                fontSize = minFont // even the smallest size overflows; scrolling/clipping takes over
            } else if measuredHeight(fontSize: maxFont, width: availableWidth) <= availableHeight {
                fontSize = maxFont // even the largest allowed size fits
            } else {
                // binary-search the largest size in [minFont, maxFont] that fits the max content area
                var lo = minFont
                var hi = maxFont
                for _ in 0..<18 {
                    let mid = (lo + hi) / 2
                    if measuredHeight(fontSize: mid, width: availableWidth) <= availableHeight {
                        lo = mid
                    } else {
                        hi = mid
                    }
                }
                fontSize = lo
            }
        }

        let attributed = attributedText(fontSize: fontSize)
        var textSize = Self.measure(attributed, width: availableWidth)

        var panelWidth = maxW
        var panelHeight = maxH
        if settings.autoSizeOverlay {
            panelWidth = min(maxW, max(minW, textSize.width + 2 * pad))
            textSize = Self.measure(attributed, width: max(50, panelWidth - 2 * pad))
            panelHeight = min(maxH, max(minH, textSize.height + 2 * pad))
        }

        // center short content vertically in the visible area
        let visibleHeight = panelHeight - 2 * pad
        let centeringInset = max(0, (visibleHeight - textSize.height) / 2)
        textView.textContainerInset = NSSize(width: 0, height: centeringInset)

        textView.textStorage?.setAttributedString(attributed)
        setFrameKeepingCenter(NSSize(width: panelWidth, height: panelHeight))
        textView.scroll(.zero)
    }

    private func attributedText(fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = settings.alignment.nsAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let color = isShowingPlaceholder
            ? settings.effectiveTextColor.withAlphaComponent(0.5)
            : settings.effectiveTextColor
        return NSAttributedString(string: isShowingPlaceholder ? placeholderMessage : currentText!,
                                  attributes: [
                                      .font: resolvedFont(size: fontSize),
                                      .foregroundColor: color,
                                      .paragraphStyle: paragraph,
                                  ])
    }

    private func measuredHeight(fontSize: CGFloat, width: CGFloat) -> CGFloat {
        Self.measure(attributedText(fontSize: fontSize), width: width).height
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        let rect = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        // small fudge so measurement rounding never clips the last line
        return CGSize(width: ceil(rect.width) + 2, height: ceil(rect.height) + 2)
    }

    private func resolvedFont(size: CGFloat) -> NSFont {
        let manager = NSFontManager.shared
        let traits: NSFontTraitMask = settings.bold ? .boldFontMask : []
        // Weight 5 is "regular", 9 is "bold" on NSFontManager's 0–15 scale.
        let weight = settings.bold ? 9 : 5
        if let font = manager.font(withFamily: settings.fontFamily,
                                   traits: traits,
                                   weight: weight,
                                   size: size) {
            return font
        }
        return settings.bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
    }

    // MARK: - Position

    /// Resize around the current center, keeping the panel on its screen.
    private func setFrameKeepingCenter(_ size: NSSize) {
        guard frame.size != size else { return }
        var origin = NSPoint(x: frame.midX - size.width / 2,
                             y: frame.midY - size.height / 2)
        if let screen = screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

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
