import AppKit

/// Search field that reports every change to `onQueryChange`, including text an input method
/// is still composing (e.g. pinyin before a candidate is picked), so results update on every key.
final class SearchField: NSTextField {
    var onQueryChange: ((String) -> Void)?

    override class var cellClass: AnyClass? {
        get { SearchFieldCell.self }
        set {}
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 24)
        placeholderString = "Search apps…"
        cell?.isScrollable = true
        cell?.wraps = false

        let editor = (cell as! SearchFieldCell).editor
        editor.onTextChange = { [unowned self, unowned editor] in
            onQueryChange?(Self.query(from: editor))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The editor's text, including marked (composing) text. Pinyin input methods insert
    /// separators while composing ("s'y's"), so those are dropped from the marked range.
    private static func query(from editor: NSTextView) -> String {
        let text = editor.string
        guard editor.hasMarkedText() else { return text }
        let marked = editor.markedRange()
        let ns = text as NSString
        let composing = ns.substring(with: marked)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "")
        return ns.replacingCharacters(in: marked, with: composing)
    }
}

/// Supplies the field editor that reports composing text.
private final class SearchFieldCell: NSTextFieldCell {
    let editor: ComposingFieldEditor = {
        // TextKit 1, like the system's own field editor; TextKit 2 costs more per keystroke.
        let editor = ComposingFieldEditor(usingTextLayoutManager: false)
        editor.isFieldEditor = true
        // A plain NSTextView picks up the user's typing features (spell checking, predictive
        // text, substitutions, …), which a search box doesn't want.
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.inlinePredictionType = .no
        editor.writingToolsBehavior = .none
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor
    }
}

/// Field editor that calls `onTextChange` for committed edits and for marked-text changes,
/// which `NSTextField`'s delegate doesn't hear about.
private final class ComposingFieldEditor: NSTextView {
    var onTextChange: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        PerfLog.measure("keyDown") { super.keyDown(with: event) }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        PerfLog.measure("insertText") { super.insertText(string, replacementRange: replacementRange) }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextChange?()
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
    }
}
