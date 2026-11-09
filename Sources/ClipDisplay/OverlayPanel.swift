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

    /// True from present() until dismiss(), including while fading. Use this, not isVisible.
    private(set) var isShown = false
    private var autoHideWork: DispatchWorkItem?
    /// Screen the fill-screen layout covers; picked on each present().
    private var targetScreen: NSScreen?
    private var wasFillScreen = false
    private static let fillScreenMargin: CGFloat = 40

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

    /// Set the displayed text and show the panel. Pass nil (with an optional placeholder
    /// message) when the clipboard has no string — e.g. empty, or an image (v2 seam).
    func show(text: String?, placeholder: String = "— no text on clipboard —") {
        currentText = text
        placeholderMessage = placeholder
        present()
    }

    // MARK: - Show / hide

    /// Lay out for the current screen, fade in, and arm the auto-hide timer.
    func present() {
        if settings.fillScreen {
            targetScreen = Self.screenUnderMouse ?? screen ?? NSScreen.main
        }
        layoutContent()

        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        isShown = true
        animateAlpha(to: 1, completion: nil)
        scheduleAutoHide()
    }

    /// Fade out, then order out (unless present() ran again during the fade).
    func dismiss() {
        isShown = false
        autoHideWork?.cancel()
        autoHideWork = nil
        animateAlpha(to: 0) { [weak self] in
            guard let self, !self.isShown else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }

    private func animateAlpha(to value: CGFloat, completion: (() -> Void)?) {
        let duration = settings.fadeDuration
        guard duration >= 0.01 else {
            alphaValue = value
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = value
        }, completionHandler: completion)
    }

    private func scheduleAutoHide() {
        autoHideWork?.cancel()
        autoHideWork = nil
        guard settings.autoHideSeconds > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        autoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoHideSeconds, execute: work)
    }

    private static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
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

        if settings.fillScreen && targetScreen == nil {
            targetScreen = screen ?? NSScreen.main
        }
        layoutContent()

        // Leaving fill-screen mode: go back to the user's saved spot.
        if wasFillScreen && !settings.fillScreen {
            targetScreen = nil
            restorePosition()
        }
        wasFillScreen = settings.fillScreen
    }

    // MARK: - Adaptive sizing

    private func layoutContent() {
        let pad = max(0, settings.padding)
        // Fill-screen mode: the max footprint is the target screen, like HotKey.
        let fillScreen = settings.fillScreen ? (targetScreen ?? screen ?? NSScreen.main) : nil
        let fillSize = fillScreen.map {
            NSSize(width: $0.visibleFrame.width - 2 * Self.fillScreenMargin,
                   height: $0.visibleFrame.height - 2 * Self.fillScreenMargin)
        }
        let maxSettingW = fillSize.map { Double($0.width) } ?? settings.overlayWidth
        let maxSettingH = fillSize.map { Double($0.height) } ?? settings.overlayHeight
        // Min width/height are a floor; the settings width/height are the max
        // footprint. Clamp the floor so it can never exceed the max.
        let minW = min(settings.minOverlayWidth, maxSettingW)
        let minH = min(settings.minOverlayHeight, maxSettingH)
        let maxW = max(maxSettingW, minW)
        let maxH = max(maxSettingH, minH)
        let availableWidth = max(50, maxW - 2 * pad)
        let availableHeight = max(30, maxH - 2 * pad)

        let minFont = max(1, min(settings.minFontSize, settings.maxFontSize))
        // Auto-size treats the chosen font size as the natural target and only
        // shrinks it to fit; a fixed-size overlay also grows the text (up to the
        // max font size) to fill the window — so the size tracks text length.
        // Fill-screen mode always grows, like a fixed-size overlay.
        let maxFont = settings.autoSizeOverlay && fillScreen == nil
            ? max(minFont, settings.fontSize)
            : max(minFont, settings.maxFontSize)

        // A size only fits if the text wraps within the height *and* its widest
        // unbreakable run fits the width — otherwise word wrapping degrades into
        // a mid-word character wrap (see longestUnbreakableRun).
        let unbreakable = Self.longestUnbreakableRun(in: displayString)
        // Overflow ratio (<= 1 fits); sqrt because wrapped text height grows about with size².
        func overflow(_ size: CGFloat) -> CGFloat {
            let widthRatio = unbreakableWidth(unbreakable, fontSize: size) / availableWidth
            let heightRatio = measuredHeight(fontSize: size, width: availableWidth) / availableHeight
            return max(widthRatio, heightRatio.squareRoot())
        }

        var fontSize = settings.fontSize
        if settings.shrinkTextToFit || fillScreen != nil {
            // Proportional fit (HotKey-style): scale by the overflow ratio and re-measure; minFont if nothing fits.
            var best = minFont
            var found = false
            var size = maxFont
            for _ in 0..<6 {
                let ratio = overflow(size)
                if ratio <= 1 {
                    best = max(best, size); found = true
                    if size >= maxFont || ratio > 0.98 { break }
                }
                let next = min(maxFont, max(minFont, size / ratio * 0.99))
                if abs(next - size) < 0.25 || (found && next <= best) { break }
                size = next
            }
            fontSize = best
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
        if let fillScreen {
            let visible = fillScreen.visibleFrame
            setFrame(NSRect(x: visible.midX - panelWidth / 2,
                            y: visible.midY - panelHeight / 2,
                            width: panelWidth,
                            height: panelHeight),
                     display: true)
        } else {
            setFrameKeepingCenter(NSSize(width: panelWidth, height: panelHeight))
        }
        textView.scroll(.zero)
    }

    private var displayString: String {
        isShowingPlaceholder ? placeholderMessage : currentText!
    }

    private func attributedText(fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = settings.alignment.nsAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let color = isShowingPlaceholder
            ? settings.effectiveTextColor.withAlphaComponent(0.5)
            : settings.effectiveTextColor
        var attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont(size: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if settings.textShadow {
            let blur = max(0, settings.textShadowBlur)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowOffset = NSSize(width: blur / 2, height: -blur / 2)
            shadow.shadowBlurRadius = blur
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: displayString, attributes: attributes)
    }

    private func measuredHeight(fontSize: CGFloat, width: CGFloat) -> CGFloat {
        Self.measure(attributedText(fontSize: fontSize), width: width).height
    }

    /// Longest whitespace-free run in the text — the widest chunk word wrapping
    /// cannot break. When it is wider than the container AppKit silently falls
    /// back to breaking mid-word, so it has to fit for a size to be usable.
    private static func longestUnbreakableRun(in text: String) -> String {
        let runs: [Substring] = text.split(whereSeparator: { $0.isWhitespace })
        guard let longest = runs.max(by: { $0.count < $1.count }) else { return "" }
        return String(longest)
    }

    /// Width of an unbreakable run laid out on one unbounded line.
    private func unbreakableWidth(_ run: String, fontSize: CGFloat) -> CGFloat {
        guard !run.isEmpty else { return 0 }
        let attributed = NSAttributedString(string: run,
                                            attributes: [.font: resolvedFont(size: fontSize)])
        return Self.measure(attributed, width: .greatestFiniteMagnitude).width
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
