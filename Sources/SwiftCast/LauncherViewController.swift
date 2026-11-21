import AppKit
import SwiftCastCore

/// The launcher's content, Spotlight-style: a glass search capsule, and below it a glass card
/// with the results, a section heading and key hints.
///
/// Plain AppKit on purpose. Every view is created up front, so typing only changes the
/// content of existing views (see `ResultsListView`). The window never resizes (see
/// `LauncherPanel`); the card fits its content and animates to new sizes with Core Animation.
@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate {
    static let width: CGFloat = 680
    /// Transparent space around the surfaces, for their shadows.
    static let margin: CGFloat = 40
    static let capsuleHeight: CGFloat = 56
    static let cardGap: CGFloat = 8
    static let cardHeaderHeight: CGFloat = 26
    static let cardHintsHeight: CGFloat = 36
    static let emptyCardHeight: CGFloat = 64
    static let maxVisibleRows = 8

    static var maxCardHeight: CGFloat {
        cardHeaderHeight + ResultsListView.height(forRows: maxVisibleRows) + cardHintsHeight
    }

    static var windowSize: NSSize {
        NSSize(width: width + margin * 2, height: margin * 2 + capsuleHeight + cardGap + maxCardHeight)
    }

    let model: LauncherViewModel
    let searchField = SearchField()

    /// What the card shows; each state has its own height (see `height(for:)`).
    private enum CardState: Equatable {
        case hidden
        case empty
        case results(rows: Int)
    }
    private var cardState = CardState.hidden
    /// What the heading and hints currently show; see `selectionChanged(animated:)`.
    private struct Footer: Equatable {
        var label: String
        var isCalculation: Bool
    }
    private var lastFooter: Footer?
    private static let appHints = [("↩", "Open"), ("⌘↩", "Show in Finder"), ("esc", "Close")]
    private static let calculationHints = [("↩", "Copy"), ("esc", "Close")]

    /// Whether the panel is on screen, so changes animate. Off while it's prepared for showing.
    private var isPresented = false
    /// Bumped on every show, so a fade-out that finishes after a reopen doesn't hide the panel.
    private var presentation = 0

    private let resultsList = ResultsListView(capacity: LauncherViewModel.itemLimit)
    private var card = NSView()
    private var cardContent = NSView()
    private let cardBody = NSView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No matching applications")
    private let sectionLabel = NSTextField(labelWithString: "")
    private let hintsView = KeyHintsView(hints: LauncherViewController.appHints)
    private let clearButton = NSButton(
        image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear search")!,
        target: nil,
        action: nil
    )

    init(model: LauncherViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private static var capsuleFrame: NSRect {
        NSRect(x: margin, y: windowSize.height - margin - capsuleHeight, width: width, height: capsuleHeight)
    }

    private static func height(for state: CardState) -> CGFloat {
        switch state {
        case .hidden: 0
        case .empty: emptyCardHeight
        case .results(let rows):
            cardHeaderHeight + ResultsListView.height(forRows: min(rows, maxVisibleRows)) + cardHintsHeight
        }
    }

    /// The card's frame for `height`, hanging below the capsule.
    private static func cardFrame(height: CGFloat) -> NSRect {
        NSRect(x: margin, y: capsuleFrame.minY - cardGap - height, width: width, height: height)
    }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
        root.wantsLayer = true

        let (container, surfaces) = GlassSurface.container()
        container.frame = root.bounds
        container.autoresizingMask = [.width, .height]
        root.addSubview(container)

        let (capsule, capsuleContent) = GlassSurface.make(cornerRadius: Self.capsuleHeight / 2)
        capsule.frame = Self.capsuleFrame
        surfaces.addSubview(capsule)
        setUpCapsule(capsuleContent)

        let (card, cardContent) = GlassSurface.make(cornerRadius: 22)
        card.wantsLayer = true
        card.isHidden = true
        surfaces.addSubview(card)
        self.card = card
        self.cardContent = cardContent
        setUpCard()

        view = root
        model.onResultsChange = { [unowned self] in resultsChanged() }
        model.onSelectionChange = { [unowned self] in selectionChanged(animated: true) }
        resultsChanged()
    }

    private func setUpCapsule(_ content: NSView) {
        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor

        searchField.delegate = self
        searchField.onQueryChange = { [unowned self] query in
            if model.query != query { model.userEdited(query) }
        }

        clearButton.isBordered = false
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        clearButton.target = self
        clearButton.action = #selector(clearQuery)
        clearButton.toolTip = "Clear search"
        clearButton.isHidden = true

        // The capsule never changes size, so these frames are set once.
        let height = Self.capsuleHeight
        icon.frame = NSRect(x: 20, y: (height - 24) / 2, width: 24, height: 24)
        clearButton.frame = NSRect(x: Self.width - 40, y: (height - 20) / 2, width: 20, height: 20)
        searchField.frame = NSRect(x: 54, y: (height - 32) / 2, width: Self.width - 54 - 48, height: 32)
        for view in [icon, searchField, clearButton] as [NSView] {
            content.addSubview(view)
        }
    }

    private func setUpCard() {
        resultsList.frame = NSRect(x: 0, y: 0, width: Self.width, height: 0)
        resultsList.onClick = { [unowned self] index in
            guard model.items.indices.contains(index) else { return }
            model.selection = index
            model.launchSelected()
        }
        resultsList.onHover = { [unowned self] index in
            if model.items.indices.contains(index) { model.selection = index }
        }

        scrollView.documentView = resultsList
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        sectionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        sectionLabel.textColor = .secondaryLabelColor

        // The body is laid out at the card's target size and pinned to its top, so while the
        // card animates to a new height its content is revealed or clipped, never stretched.
        cardBody.autoresizingMask = [.width, .minYMargin]
        for view in [sectionLabel, scrollView, emptyLabel, hintsView] as [NSView] {
            cardBody.addSubview(view)
        }
        cardContent.addSubview(cardBody)
    }

    /// Lays out the card's content for `state`, at its final height.
    private func layOutCardBody(for state: CardState) {
        let width = Self.width
        let height = Self.height(for: state)
        cardBody.frame = NSRect(x: 0, y: cardContent.bounds.height - height, width: width, height: height)

        let isResults = if case .results = state { true } else { false }
        sectionLabel.isHidden = !isResults
        scrollView.isHidden = !isResults
        hintsView.isHidden = !isResults
        emptyLabel.isHidden = state != .empty

        sectionLabel.frame = NSRect(x: 20, y: height - 21, width: 300, height: 15)
        scrollView.frame = NSRect(
            x: 0,
            y: Self.cardHintsHeight,
            width: width,
            height: max(height - Self.cardHeaderHeight - Self.cardHintsHeight, 0)
        )
        layOutHints()
        emptyLabel.frame = NSRect(x: 0, y: (height - 18) / 2, width: width, height: 18)

        let listWidth = scrollView.contentSize.width
        if resultsList.frame.width != listWidth {
            resultsList.setFrameSize(NSSize(width: listWidth, height: resultsList.frame.height))
        }
    }

    private func layOutHints() {
        let size = hintsView.intrinsicContentSize
        hintsView.frame = NSRect(
            x: Self.width - 20 - size.width,
            y: (Self.cardHintsHeight - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Moves the card to `state`: fading it in or out, or animating its height.
    private func setCardState(_ state: CardState) {
        let old = cardState
        guard state != old else { return }
        cardState = state
        let animated = isPresented
        card.layer?.removeAllAnimations()

        guard state != .hidden else {
            guard animated else {
                card.isHidden = true
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                card.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                // Animation completions run on the main thread.
                MainActor.assumeIsolated {
                    guard let self, self.cardState == .hidden else { return }
                    self.card.isHidden = true
                    self.card.alphaValue = 1
                }
            }
            return
        }

        let target = Self.cardFrame(height: Self.height(for: state))
        if old == .hidden || card.isHidden {
            // Appear: slide down a little from under the capsule while fading in.
            card.frame = target
            layOutCardBody(for: state)
            card.isHidden = false
            guard animated else {
                card.alphaValue = 1
                return
            }
            card.alphaValue = 0
            card.frame = target.offsetBy(dx: 0, dy: 6)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                card.animator().alphaValue = 1
                card.animator().frame = target
            }
            return
        }

        card.alphaValue = 1
        layOutCardBody(for: state)
        guard animated else {
            card.frame = target
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().frame = target
        }
    }

    // MARK: - Showing and hiding

    /// Fades and scales the content in. Call right after the panel is ordered front.
    func animateIn() {
        presentation += 1
        isPresented = true
        guard let layer = view.layer else { return }
        layer.removeAllAnimations()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: Self.scaleTransform(0.98))
        scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        let group = CAAnimationGroup()
        group.animations = [fade, scale]
        group.duration = 0.15
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "present")
    }

    /// Fades the content out, then calls `completion` unless the panel was shown again meanwhile.
    func animateOut(completion: @escaping () -> Void) {
        isPresented = false
        let current = presentation
        guard let layer = view.layer else { return completion() }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentation == current else { return }
                layer.removeAnimation(forKey: "dismiss")
                completion()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.1
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "dismiss")
        CATransaction.commit()
    }

    /// Scales by `factor` around the top center of the capsule.
    private static func scaleTransform(_ factor: CGFloat) -> CATransform3D {
        let anchor = CGPoint(x: windowSize.width / 2, y: capsuleFrame.maxY)
        var transform = CATransform3DMakeTranslation(anchor.x, anchor.y, 0)
        transform = CATransform3DScale(transform, factor, factor, 1)
        return CATransform3DTranslate(transform, -anchor.x, -anchor.y, 0)
    }

    /// Exercises the typing path once (focus, insert text, search, fill rows) so its one-time
    /// setup happens before the user's first key. `prepareForShow(restoring:)` clears it afterward.
    func prewarm() {
        view.window?.makeFirstResponder(searchField)
        (searchField.currentEditor() as? NSTextView)?.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Readies the panel to be ordered front: either clears the search, or (`restoring`) keeps
    /// the last one with its text selected, so typing replaces it.
    func prepareForShow(restoring: Bool) {
        isPresented = false
        if restoring && !model.query.isEmpty {
            model.restore()
            if searchField.currentEditor() == nil {
                view.window?.makeFirstResponder(searchField)  // selects all on its own
            } else {
                searchField.currentEditor()?.selectAll(nil)
            }
            return
        }
        searchField.stringValue = ""
        model.reset()
        // Usually the field is still being edited from last time; re-focusing it would tear
        // down and rebuild its field editor.
        if searchField.currentEditor() == nil {
            PerfLog.measure("focus") { _ = view.window?.makeFirstResponder(searchField) }
        }
    }

    // MARK: - Model → view

    private func resultsChanged() {
        // Empty results only hide the list, leaving its rows as they are, so the next query
        // changes as few rows as possible.
        if !model.items.isEmpty {
            PerfLog.measure("reload") { resultsList.update(model.items, detail: model.detail(for:)) }
        }
        let hasQuery = !model.query.isEmpty
        if clearButton.isHidden == hasQuery {
            clearButton.isHidden = !hasQuery
        }
        let state: CardState = if !model.items.isEmpty {
            .results(rows: model.items.count)
        } else {
            hasQuery ? .empty : .hidden
        }
        setCardState(state)
        selectionChanged(animated: false)
    }

    /// Moves the highlight, and switches the heading and hints between a calculation's and an
    /// app's. Only touches them when they change, since even an identical `stringValue`
    /// redraws its label.
    private func selectionChanged(animated: Bool) {
        let index = model.items.indices.contains(model.selection) ? model.selection : nil
        resultsList.select(index, animated: animated && isPresented)
        let isCalculation = if case .calculation = model.selectedItem { true } else { false }
        let label = isCalculation ? "Calculator" : model.query.isEmpty ? "Recent" : "Applications"
        let footer = Footer(label: label, isCalculation: isCalculation)
        guard footer != lastFooter else { return }
        lastFooter = footer
        sectionLabel.stringValue = label
        hintsView.hints = isCalculation ? Self.calculationHints : Self.appHints
        layOutHints()
    }

    @objc private func clearQuery() {
        searchField.stringValue = ""
        model.query = ""
        if searchField.currentEditor() == nil {
            view.window?.makeFirstResponder(searchField)
        }
    }

    // MARK: - NSTextFieldDelegate

    // While an input method is composing, it consumes ↩/↑/↓/Esc itself, so these
    // commands only arrive when the text is plain.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            showHistoryText(model.moveDown())
        case #selector(NSResponder.moveUp(_:)):
            showHistoryText(model.moveUp())
        case #selector(NSResponder.insertNewline(_:)):
            model.launchSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            model.onDismiss()
        case NSSelectorFromString("noop:") where Self.isCommandReturn(NSApp.currentEvent):
            model.revealSelected()
        default:
            return false
        }
        return true
    }

    /// Puts a search recalled from history in the field, caret at the end.
    private func showHistoryText(_ text: String?) {
        guard let text else { return }
        searchField.stringValue = text
        searchField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    private static func isCommandReturn(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return event.modifierFlags.contains(.command)
            && (event.keyCode == 36 || event.keyCode == 76) // return, keypad enter
    }
}

/// Keyboard hints drawn as key caps followed by their action, e.g. [↩] Open.
/// Drawn in one pass, with no subviews.
private final class KeyHintsView: NSView {
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let capHeight: CGFloat = 18
    private static let capPadding: CGFloat = 5
    private static let gap: CGFloat = 5
    private static let spacing: CGFloat = 14

    var hints: [(keys: String, action: String)] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    init(hints: [(keys: String, action: String)]) {
        self.hints = hints
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: NSSize {
        let width = hints.enumerated().reduce(CGFloat(0)) { total, item in
            total + (item.offset > 0 ? Self.spacing : 0) + Self.width(of: item.element)
        }
        return NSSize(width: ceil(width), height: Self.capHeight)
    }

    private static func width(of hint: (keys: String, action: String)) -> CGFloat {
        capWidth(hint.keys) + gap + ceil(hint.action.size(withAttributes: [.font: font]).width)
    }

    private static func capWidth(_ keys: String) -> CGFloat {
        max(ceil(keys.size(withAttributes: [.font: font]).width) + capPadding * 2, capHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let keyAttributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
        let actionAttributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.tertiaryLabelColor]
        let textHeight = ("A" as NSString).size(withAttributes: keyAttributes).height
        let textY = (bounds.height - textHeight) / 2
        var x: CGFloat = 0
        for hint in hints {
            let capWidth = Self.capWidth(hint.keys)
            let cap = NSRect(x: x, y: (bounds.height - Self.capHeight) / 2, width: capWidth, height: Self.capHeight)
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: cap, xRadius: 4, yRadius: 4).fill()
            let keysWidth = hint.keys.size(withAttributes: keyAttributes).width
            hint.keys.draw(at: NSPoint(x: cap.midX - keysWidth / 2, y: textY), withAttributes: keyAttributes)
            x = cap.maxX + Self.gap
            hint.action.draw(at: NSPoint(x: x, y: textY), withAttributes: actionAttributes)
            x += ceil(hint.action.size(withAttributes: actionAttributes).width) + Self.spacing
        }
    }
}
