import AppKit
import SwiftCastCore

/// The launcher's content: a search field over the results list and a footer of key hints.
///
/// Plain AppKit on purpose. Every view is created up front, so typing only changes the
/// content of existing views (see `ResultsListView`). The panel is just the search field until
/// there is something to show, then a fixed `maxVisibleRows` rows tall, however many results
/// there are: resizing a window costs one to two frames on screen, felt as lag while typing.
@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate {
    static let headerHeight: CGFloat = 60
    static let footerHeight: CGFloat = 32
    static let maxVisibleRows = 8

    let model: LauncherViewModel
    let searchField = SearchField()
    /// Called with the height the panel should have whenever the content changes.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    private let resultsList = ResultsListView(capacity: LauncherViewModel.itemLimit)
    /// What the views outside the list currently show; see `resultsChanged()`.
    private struct Chrome: Equatable {
        var isEmpty: Bool
        var hasQuery: Bool
    }
    private var lastChrome: Chrome?
    /// What the footer currently shows; see `selectionChanged()`.
    private struct Footer: Equatable {
        var label: String
        var isCalculation: Bool
    }
    private var lastFooter: Footer?
    private static let appHints = [("↩", "Open"), ("⌘↩", "Show in Finder"), ("esc", "Close")]
    private static let calculationHints = [("↩", "Copy"), ("esc", "Close")]
    private let scrollView = NSScrollView()
    private let headerSeparator = NSBox()
    private let footerSeparator = NSBox()
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

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: LauncherPanel.width, height: Self.headerHeight))

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
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

        headerSeparator.boxType = .separator
        footerSeparator.boxType = .separator

        resultsList.frame = NSRect(x: 0, y: 0, width: LauncherPanel.width, height: 0)
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
        sectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sectionLabel.textColor = .tertiaryLabelColor

        // The header uses constraints; the body below it is laid out by frame in
        // `viewDidLayout()`, since parts of it come and go as the panel changes height.
        for view in [icon, searchField, clearButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        for view in [headerSeparator, scrollView, emptyLabel, footerSeparator, sectionLabel, hintsView] as [NSView] {
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),

            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            clearButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            clearButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
        ])

        view = root
        model.onResultsChange = { [unowned self] in resultsChanged() }
        model.onSelectionChange = { [unowned self] in selectionChanged() }
        resultsChanged()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = view.bounds.width
        let bodyTop = view.bounds.height - Self.headerHeight
        headerSeparator.frame = NSRect(x: 0, y: bodyTop - 1, width: width, height: 1)

        let footerHeight = footerSeparator.isHidden ? 0 : Self.footerHeight
        footerSeparator.frame = NSRect(x: 0, y: footerHeight - 1, width: width, height: 1)
        sectionLabel.frame = NSRect(x: 18, y: (footerHeight - 15) / 2, width: 200, height: 15)
        let hintsSize = hintsView.intrinsicContentSize
        hintsView.frame = NSRect(
            x: width - 18 - hintsSize.width,
            y: (footerHeight - hintsSize.height) / 2,
            width: hintsSize.width,
            height: hintsSize.height
        )

        scrollView.frame = NSRect(x: 0, y: footerHeight, width: width, height: max(bodyTop - 1 - footerHeight, 0))
        emptyLabel.frame = NSRect(x: 0, y: (bodyTop - 18) / 2, width: width, height: 18)

        let listWidth = scrollView.contentSize.width
        if resultsList.frame.width != listWidth {
            resultsList.setFrameSize(NSSize(width: listWidth, height: resultsList.frame.height))
        }
    }

    /// The panel height for the current content: the search field alone, or full height.
    private var preferredHeight: CGFloat {
        if model.items.isEmpty && model.query.isEmpty { return Self.headerHeight }
        return Self.headerHeight + 1 + ResultsListView.height(forRows: Self.maxVisibleRows) + Self.footerHeight
    }

    /// Exercises the typing path once (focus, insert text, search, fill rows) so its one-time
    /// setup happens before the user's first key. `prepareForShow(restoring:)` clears it afterward.
    func prewarm() {
        view.window?.makeFirstResponder(searchField)
        (searchField.currentEditor() as? NSTextView)?.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Clears the query and focuses the field. Call before the panel is ordered front.
    /// Readies the panel to be ordered front: either clears the search, or (`restoring`) keeps
    /// the last one with its text selected, so typing replaces it.
    func prepareForShow(restoring: Bool) {
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
        // Most keys change only the rows. The chrome and layout are touched only when they
        // change, since even an identical `stringValue` redraws its label.
        let isEmpty = model.items.isEmpty
        let chrome = Chrome(isEmpty: isEmpty, hasQuery: !model.query.isEmpty)
        if chrome != lastChrome {
            lastChrome = chrome
            scrollView.isHidden = isEmpty
            footerSeparator.isHidden = isEmpty
            sectionLabel.isHidden = isEmpty
            hintsView.isHidden = isEmpty
            clearButton.isHidden = !chrome.hasQuery
            headerSeparator.isHidden = isEmpty && !chrome.hasQuery
            emptyLabel.isHidden = !isEmpty || !chrome.hasQuery
            view.needsLayout = true
        }
        let height = preferredHeight
        if height != view.frame.height {
            onHeightChange(height)
            view.needsLayout = true
        }
        selectionChanged()
    }

    /// Moves the highlight, and switches the footer between a calculation's hints and an app's.
    private func selectionChanged() {
        resultsList.select(model.items.indices.contains(model.selection) ? model.selection : nil)
        let isCalculation = if case .calculation = model.selectedItem { true } else { false }
        let label = isCalculation ? "Calculator" : model.query.isEmpty ? "Recent" : "Applications"
        let footer = Footer(label: label, isCalculation: isCalculation)
        guard footer != lastFooter else { return }
        lastFooter = footer
        sectionLabel.stringValue = label
        hintsView.hints = isCalculation ? Self.calculationHints : Self.appHints
        view.needsLayout = true
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
