import AppKit
import SwiftCastCore

/// The results list: a fixed pool of row views, created once.
///
/// Results are capped (`SearchEngine.results(limit:)`), so the list never needs more rows
/// than the pool holds. Updating it sets the content of rows whose app changed and hides
/// the rest, so no views are created or torn down while the user types. One highlight view
/// behind the rows marks the selection, and slides when the selection moves.
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
    private let highlight = SelectionHighlight()
    private var count = 0
    private var selectedIndex: Int?

    init(capacity: Int) {
        rows = (0..<capacity).map { _ in ResultRowView() }
        super.init(frame: .zero)
        highlight.isHidden = true
        addSubview(highlight)
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

    /// Shows `items` (at most `capacity`), touching only rows whose content changed.
    /// `detail` gives the grey text that tells apart apps sharing a name.
    func update(_ items: [LauncherItem], detail: (AppEntry) -> String?) {
        let newCount = min(items.count, rows.count)
        for index in 0..<newCount {
            let item = items[index]
            switch item {
            case .app(let result): rows[index].configure(with: item, detail: detail(result.app))
            case .calculation(let calculation): rows[index].configure(with: item, detail: "= " + calculation.expression)
            }
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

    /// Highlights row `index`, sliding the highlight there when `animated` (the selection
    /// moved) or jumping when not (new results replaced the rows).
    func select(_ index: Int?, animated: Bool) {
        let index = index.flatMap { $0 < count ? $0 : nil }
        guard let index else {
            highlight.isHidden = true
            selectedIndex = nil
            return
        }
        let target = rows[index].frame
        if animated && !highlight.isHidden && highlight.frame != target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                highlight.animator().frame = target
            }
        } else {
            highlight.layer?.removeAllAnimations()
            highlight.frame = target
        }
        highlight.isHidden = false
        selectedIndex = index
        reveal(target.insetBy(dx: 0, dy: -Self.inset))
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
/// text for apps that share a name. A calculation shows its result, with the expression as
/// the detail. Laid out with frames, which is cheaper than constraints for a view this simple.
private final class ResultRowView: NSView {
    private static let nameFont = NSFont.systemFont(ofSize: 14)
    private static let matchFont = NSFont.systemFont(ofSize: 14, weight: .bold)
    private static let calculatorPath = "/System/Applications/Calculator.app"

    var onClick: () -> Void = {}

    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var item: LauncherItem?
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

    func configure(with item: LauncherItem, detail: String?) {
        guard item != self.item || detail != self.detail else { return }
        let iconPath = Self.iconPath(for: item)
        if self.item.map(Self.iconPath) != iconPath {
            icon.image = IconCache.shared.icon(for: iconPath)
        }
        self.item = item
        self.detail = detail
        switch item {
        case .app(let result):
            nameLabel.attributedStringValue = Self.name(result.app.name, bolding: result.matchedIndices)
        case .calculation(let calculation):
            nameLabel.attributedStringValue = Self.name(calculation.display, bolding: Array(0..<calculation.display.count))
        }
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
        needsLayout = true
    }

    private static func iconPath(for item: LauncherItem) -> String {
        switch item {
        case .app(let result): result.app.url.path
        case .calculation: calculatorPath
        }
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

/// The rounded highlight behind the selected row.
private final class SelectionHighlight: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }

    // Runs with the view's appearance current, so the color follows light and dark.
    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }
}
