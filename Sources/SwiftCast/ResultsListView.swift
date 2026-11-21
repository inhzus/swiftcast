import AppKit
import SwiftCastCore

/// The results list: a fixed pool of row views, created once.
///
/// Results are capped (`SearchEngine.results(limit:)`), so the list never needs more rows
/// than the pool holds. Updating it sets the content of rows whose app changed and hides
/// the rest, so no views are created or torn down while the user types.
final class ResultsListView: NSView {
    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 2
    static let inset: CGFloat = 8

    var onClick: (Int) -> Void = { _ in }

    /// Height of a list showing `rows` rows.
    static func height(forRows rows: Int) -> CGFloat {
        inset * 2 + CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
    }

    private let rows: [ResultRowView]
    private var count = 0
    private var selectedIndex: Int?

    init(capacity: Int) {
        rows = (0..<capacity).map { _ in ResultRowView() }
        super.init(frame: .zero)
        for (index, row) in rows.enumerated() {
            row.isHidden = true
            row.onClick = { [unowned self] in onClick(index) }
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    /// Shows `results` (at most `capacity`), touching only rows whose app changed.
    func update(_ results: [AppEntry]) {
        let newCount = min(results.count, rows.count)
        for index in 0..<newCount {
            rows[index].configure(with: results[index])
            rows[index].isHidden = false
        }
        for index in newCount..<max(count, newCount) {
            rows[index].isHidden = true
        }
        count = newCount
        let height = Self.height(forRows: newCount)
        if frame.height != height {
            setFrameSize(NSSize(width: frame.width, height: height))
        }
    }

    func select(_ index: Int?) {
        let index = index.flatMap { $0 < count ? $0 : nil }
        if index != selectedIndex {
            if let old = selectedIndex { rows[old].isSelected = false }
            if let index { rows[index].isSelected = true }
            selectedIndex = index
        }
        reveal(index.map { rows[$0].frame.insetBy(dx: 0, dy: -Self.inset) } ?? .zero)
    }

    /// Scrolls the minimum distance to show `rect`, immediately. `scrollToVisible` animates,
    /// and key repeat outpaces the animation, so queued scrolls overshoot the selection.
    private func reveal(_ rect: NSRect) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let visibleHeight = clip.bounds.height
        var y = clip.bounds.origin.y
        if rect.minY < y {
            y = rect.minY
        } else if rect.maxY > y + visibleHeight {
            y = rect.maxY - visibleHeight
        }
        y = max(0, min(y, bounds.height - visibleHeight))
        guard y != clip.bounds.origin.y else { return }
        clip.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    // Rows are positioned whenever the list is resized, rather than in `layout()`, which a
    // frame-based document view isn't guaranteed to receive.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { layoutRows() }
    }

    private func layoutRows() {
        let width = bounds.width - Self.inset * 2
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: Self.inset,
                y: Self.inset + CGFloat(index) * (Self.rowHeight + Self.rowSpacing),
                width: width,
                height: Self.rowHeight
            )
        }
    }
}

/// Icon, app name, and containing folder, with a soft rounded highlight when selected.
/// Laid out with frames, which is cheaper than constraints for a view this simple.
private final class ResultRowView: NSView {
    var onClick: () -> Void = {}
    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private var app: AppEntry?

    init() {
        super.init(frame: .zero)
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        for view in [icon, nameLabel, pathLabel] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(with app: AppEntry) {
        guard app != self.app else { return }
        self.app = app
        icon.image = IconCache.shared.icon(for: app.url.path)
        nameLabel.stringValue = app.name
        pathLabel.stringValue = (app.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func layout() {
        super.layout()
        let textX: CGFloat = 54
        let textWidth = max(bounds.width - textX - 10, 0)
        icon.frame = NSRect(x: 10, y: (bounds.height - 32) / 2, width: 32, height: 32)
        nameLabel.frame = NSRect(x: textX, y: bounds.midY, width: textWidth, height: 18)
        pathLabel.frame = NSRect(x: textX, y: bounds.midY - 16, width: textWidth, height: 15)
    }
}
