import AppKit
import SwiftCastCore

/// The launcher's content: a search field over the results list and a footer of key hints.
///
/// Plain AppKit on purpose. Every view is created up front, so typing only changes the
/// content of existing views (see `ResultsListView`). The panel is as tall as its content:
/// just the search field until there is something to show, then up to `maxVisibleRows` rows.
@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate {
    static let headerHeight: CGFloat = 60
    static let footerHeight: CGFloat = 32
    static let messageHeight: CGFloat = 64
    static let maxVisibleRows = 8

    let model: LauncherViewModel
    let searchField = SearchField()
    /// Called with the height the panel should have whenever the content changes.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    private let resultsList = ResultsListView(capacity: LauncherViewModel.resultLimit)
    private let scrollView = NSScrollView()
    private let headerSeparator = NSBox()
    private let footerSeparator = NSBox()
    private let emptyLabel = NSTextField(labelWithString: "No matching applications")
    private let sectionLabel = NSTextField(labelWithString: "")
    private let hintsLabel = NSTextField(labelWithAttributedString: LauncherViewController.hints)

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
            if model.query != query { model.query = query }
        }

        headerSeparator.boxType = .separator
        footerSeparator.boxType = .separator

        resultsList.frame = NSRect(x: 0, y: 0, width: LauncherPanel.width, height: 0)
        resultsList.onClick = { [unowned self] index in
            guard model.results.indices.contains(index) else { return }
            model.selection = index
            model.launchSelected()
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
        for view in [icon, searchField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        for view in [headerSeparator, scrollView, emptyLabel, footerSeparator, sectionLabel, hintsLabel] as [NSView] {
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),

            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 28),
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
        let labelY = (footerHeight - 15) / 2
        sectionLabel.frame = NSRect(x: 18, y: labelY, width: 200, height: 15)
        let hintsWidth = ceil(Self.hints.size().width) + 4
        hintsLabel.frame = NSRect(x: width - 18 - hintsWidth, y: labelY, width: hintsWidth, height: 15)

        scrollView.frame = NSRect(x: 0, y: footerHeight, width: width, height: max(bodyTop - 1 - footerHeight, 0))
        emptyLabel.frame = NSRect(x: 0, y: (bodyTop - 18) / 2, width: width, height: 18)

        let listWidth = scrollView.contentSize.width
        if resultsList.frame.width != listWidth {
            resultsList.setFrameSize(NSSize(width: listWidth, height: resultsList.frame.height))
        }
    }

    /// The panel height that fits the current content.
    private var preferredHeight: CGFloat {
        if !model.results.isEmpty {
            let rows = min(model.results.count, Self.maxVisibleRows)
            return Self.headerHeight + 1 + ResultsListView.height(forRows: rows) + Self.footerHeight
        }
        return model.query.isEmpty ? Self.headerHeight : Self.headerHeight + Self.messageHeight
    }

    /// "Open ↩   Show in Finder ⌘↩", with the keys a step brighter than their actions.
    private static let hints: NSAttributedString = {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let action: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let key: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let text = NSMutableAttributedString()
        for (index, (name, keys)) in [("Open", "↩"), ("Show in Finder", "⌘↩")].enumerated() {
            text.append(NSAttributedString(string: (index > 0 ? "     " : "") + name + "  ", attributes: action))
            text.append(NSAttributedString(string: keys, attributes: key))
        }
        return text
    }()

    /// Exercises the typing path once (focus, insert text, search, fill rows) so its one-time
    /// setup happens before the user's first key. `prepareForShow()` clears it afterward.
    func prewarm() {
        view.window?.makeFirstResponder(searchField)
        (searchField.currentEditor() as? NSTextView)?.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Clears the query and focuses the field. Call before the panel is ordered front.
    func prepareForShow() {
        searchField.stringValue = ""
        model.query = ""
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
        if !model.results.isEmpty {
            PerfLog.measure("reload") { resultsList.update(model.results) }
        }
        let isEmpty = model.results.isEmpty
        scrollView.isHidden = isEmpty
        footerSeparator.isHidden = isEmpty
        sectionLabel.isHidden = isEmpty
        hintsLabel.isHidden = isEmpty
        headerSeparator.isHidden = isEmpty && model.query.isEmpty
        emptyLabel.isHidden = !isEmpty || model.query.isEmpty
        sectionLabel.stringValue = model.query.isEmpty ? "Recent" : "Applications"
        onHeightChange(preferredHeight)
        view.needsLayout = true
        selectionChanged()
    }

    private func selectionChanged() {
        resultsList.select(model.results.indices.contains(model.selection) ? model.selection : nil)
    }

    // MARK: - NSTextFieldDelegate

    // While an input method is composing, it consumes ↩/↑/↓/Esc itself, so these
    // commands only arrive when the text is plain.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(by: -1)
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

    private static func isCommandReturn(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return event.modifierFlags.contains(.command)
            && (event.keyCode == 36 || event.keyCode == 76) // return, keypad enter
    }
}
