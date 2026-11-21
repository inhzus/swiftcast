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
    /// Called when the mouse moves onto a row. Only real movement reports, so a resting
    /// pointer doesn't take the selection from the keyboard as rows change under it.
    var onHover: (Int) -> Void = { _ in }

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
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    /// Shows `results` (at most `capacity`), touching only rows whose content changed.
    func update(_ results: [SearchResult], detail: (AppEntry) -> String?) {
        let newCount = min(results.count, rows.count)
        for index in 0..<newCount {
            rows[index].configure(with: results[index], detail: detail(results[index].app))
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

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = rows.prefix(count).firstIndex(where: { $0.frame.contains(point) }) {
            onHover(index)
        }
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

/// Icon and app name, with the letters that matched the query in bold, plus grey detail
/// text for apps that share a name. A soft rounded highlight marks the selection.
/// Laid out with frames, which is cheaper than constraints for a view this simple.
private final class ResultRowView: NSView {
    private static let nameFont = NSFont.systemFont(ofSize: 14)
    private static let matchFont = NSFont.systemFont(ofSize: 14, weight: .bold)

    var onClick: () -> Void = {}
    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var result: SearchResult?
    private var detail: String?

    init() {
        super.init(frame: .zero)
        nameLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        for view in [icon, nameLabel, detailLabel] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(with result: SearchResult, detail: String?) {
        guard result != self.result || detail != self.detail else { return }
        if result.app != self.result?.app {
            icon.image = IconCache.shared.icon(for: result.app.url.path)
        }
        self.result = result
        self.detail = detail
        nameLabel.attributedStringValue = Self.name(result.app.name, bolding: result.matchedIndices)
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
        needsLayout = true
    }

    /// `name` with the characters at `indices` (Character offsets) in bold.
    private static func name(_ name: String, bolding indices: [Int]) -> NSAttributedString {
        let text = NSMutableAttributedString(string: name, attributes: [
            .font: nameFont,
            .foregroundColor: NSColor.labelColor,
        ])
        guard !indices.isEmpty else { return text }
        let matched = Set(indices)
        var offset = 0
        for (index, character) in name.enumerated() {
            let length = character.utf16.count
            if matched.contains(index) {
                text.addAttribute(.font, value: matchFont, range: NSRange(location: offset, length: length))
            }
            offset += length
        }
        return text
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func layout() {
        super.layout()
        let textX: CGFloat = 54
        let maxX = bounds.width - 12
        let y = (bounds.height - 18) / 2
        icon.frame = NSRect(x: 10, y: (bounds.height - 32) / 2, width: 32, height: 32)
        var nameWidth = max(maxX - textX, 0)
        if !detailLabel.isHidden {
            nameWidth = min(ceil(nameLabel.attributedStringValue.size().width) + 4, nameWidth * 0.6)
            let detailX = textX + nameWidth + 6
            detailLabel.frame = NSRect(x: detailX, y: y, width: max(maxX - detailX, 0), height: 17)
        }
        nameLabel.frame = NSRect(x: textX, y: y, width: nameWidth, height: 18)
    }
}
