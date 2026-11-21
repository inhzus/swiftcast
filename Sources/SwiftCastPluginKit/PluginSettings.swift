import Foundation

// A plugin describes its Settings page as values; the app draws it. When the user changes a
// row the app calls `setSetting`, or `performSettingsAction` for a button, then asks for
// `settingsSections()` again and redraws. The plugin keeps the values; the app doesn't.

/// A group of rows on the plugin's Settings page.
public struct SettingsSection: Hashable, Sendable {
    public var title: String?
    /// Grey text below the rows.
    public var footer: String?
    public var rows: [SettingsRow]

    public init(_ title: String? = nil, footer: String? = nil, rows: [SettingsRow]) {
        self.title = title
        self.footer = footer
        self.rows = rows
    }
}

public struct SettingsRow: Hashable, Sendable {
    /// Passed back to `setSetting` or `performSettingsAction`; unique on the page.
    public var id: String
    /// The row's label. A `folders` row shows only its folders.
    public var title: String
    /// Grey text below the title.
    public var detail: String?
    public var control: SettingsControl

    public init(id: String, title: String, detail: String? = nil, control: SettingsControl) {
        self.id = id
        self.title = title
        self.detail = detail
        self.control = control
    }
}

public enum SettingsControl: Hashable, Sendable {
    /// A switch; changes arrive as `.bool`.
    case toggle(Bool)
    /// A pop-up menu; changes arrive as `.choice` with the chosen option's id.
    case choice(selected: String, options: [SettingsOption])
    /// A list of folders: `fixed` ones shown greyed out, `editable` ones with a remove button,
    /// and an "Add Folder…" button whose open panel shows `addPrompt`. Changes arrive as
    /// `.folders` with the new `editable` list.
    case folders(fixed: [URL], editable: [URL], addPrompt: String)
    /// A button with this title; pressing it, after `confirmation` if any, calls
    /// `performSettingsAction`.
    case button(String, enabled: Bool = true, confirmation: SettingsConfirmation? = nil)
    /// Read-only text.
    case value(String)
}

public struct SettingsOption: Hashable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// An alert shown before a button's action runs.
public struct SettingsConfirmation: Hashable, Sendable {
    public var title: String
    public var message: String
    /// The alert's confirming button, e.g. "Clear".
    public var action: String
    public var destructive: Bool

    public init(title: String, message: String, action: String, destructive: Bool = false) {
        self.title = title
        self.message = message
        self.action = action
        self.destructive = destructive
    }
}

/// A row's new value, matching its control.
public enum SettingsValue: Hashable, Sendable {
    case bool(Bool)
    case choice(String)
    case folders([URL])
}
