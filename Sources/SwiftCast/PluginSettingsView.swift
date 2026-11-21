import AppKit
import SwiftCastPluginKit
import SwiftUI

/// UI state for the plugin pages. An observable object rather than `@State`, which is a macro
/// whose plugin ships only with Xcode, not the Command Line Tools this project builds with.
@MainActor
@Observable
final class PluginSettingsState {
    /// Bumped after every call into a plugin, so the page asks it for its sections again.
    var revision = 0
    /// The button row whose confirmation is showing.
    var confirming: String?
}

/// A plugin's `settingsSections()`, drawn as `Section`s of the page's `Form`.
struct PluginSettingsSections: View {
    let plugin: any LauncherPlugin
    @Bindable var state: PluginSettingsState

    var body: some View {
        let _ = state.revision
        ForEach(Array(plugin.settingsSections().enumerated()), id: \.offset) { _, section in
            Section {
                ForEach(section.rows, id: \.id) { row in
                    rowView(row)
                }
            } header: {
                if let title = section.title { Text(title) }
            } footer: {
                if let footer = section.footer {
                    Text(footer).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: SettingsRow) -> some View {
        switch row.control {
        case .toggle(let isOn):
            Toggle(isOn: Binding(get: { isOn }, set: { set(row.id, .bool($0)) })) {
                label(row)
            }
        case .choice(let selected, let options):
            Picker(selection: Binding(get: { selected }, set: { set(row.id, .choice($0)) })) {
                ForEach(options, id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            } label: {
                label(row)
            }
        case .folders(let fixed, let editable, let addPrompt):
            ForEach(fixed, id: \.self) { folder in
                HStack {
                    folderLabel(folder).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help("Always searched")
                }
            }
            ForEach(editable, id: \.self) { folder in
                HStack {
                    folderLabel(folder)
                    Spacer()
                    Button {
                        set(row.id, .folders(editable.filter { $0 != folder }))
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this folder")
                }
            }
            Button("Add Folder…") {
                let picked = Self.pickFolders(prompt: addPrompt)
                if !picked.isEmpty { set(row.id, .folders(editable + picked)) }
            }
        case .button(let title, let enabled, let confirmation):
            LabeledContent {
                Button(title) {
                    if confirmation == nil { perform(row.id) } else { state.confirming = row.id }
                }
                .disabled(!enabled)
            } label: {
                label(row)
            }
            .alert(confirmation?.title ?? "", isPresented: Binding(
                get: { state.confirming == row.id },
                set: { if !$0 { state.confirming = nil } }
            )) {
                if let confirmation {
                    Button(confirmation.action, role: confirmation.destructive ? .destructive : nil) {
                        perform(row.id)
                    }
                }
            } message: {
                Text(confirmation?.message ?? "")
            }
        case .number(let number, let range):
            let clamp = { min(max($0, range.lowerBound), range.upperBound) }
            LabeledContent {
                HStack(spacing: 4) {
                    NumberField(value: number) { set(row.id, .int(clamp($0))) }
                        .frame(width: 64)
                    Stepper("", value: Binding(get: { number }, set: { set(row.id, .int(clamp($0))) }), in: range)
                        .labelsHidden()
                }
            } label: {
                label(row)
            }
        case .value(let value):
            LabeledContent {
                Text(value)
            } label: {
                label(row)
            }
        }
    }

    @ViewBuilder
    private func label(_ row: SettingsRow) -> some View {
        Text(row.title)
        if let detail = row.detail { Text(detail) }
    }

    /// A folder's path beside its Finder icon.
    private func folderLabel(_ folder: URL) -> some View {
        Label {
            Text(Self.displayPath(folder))
        } icon: {
            Image(nsImage: IconCache.shared.icon(for: folder.path)).resizable().frame(width: 16, height: 16)
        }
    }

    private func set(_ id: String, _ value: SettingsValue) {
        plugin.setSetting(id, to: value)
        state.revision += 1
    }

    private func perform(_ id: String) {
        plugin.performSettingsAction(id)
        state.revision += 1
    }

    private static func pickFolders(prompt: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.urls : []
    }

    private static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// A number field that reports a new value only when editing ends (↩, Tab, clicking
/// elsewhere, or leaving the page), not on every key: lowering a limit can delete data, so
/// "100" mustn't pass through 1. Text that isn't a number puts the current value back.
private struct NumberField: NSViewRepresentable {
    let value: Int
    let onCommit: (Int) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = CommitOnRemovalField(string: String(value))
        field.alignment = .right
        field.delegate = context.coordinator
        // SwiftUI can release the coordinator before removing the field, so hold it strongly;
        // it doesn't hold the field.
        let coordinator = context.coordinator
        field.onRemoval = { coordinator.commit($0) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil && field.stringValue != String(value) {
            field.stringValue = String(value)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumberField

        init(parent: NumberField) {
            self.parent = parent
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commit(field)
        }

        func commit(_ field: NSTextField) {
            guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else {
                field.stringValue = String(parent.value)
                return
            }
            guard value != parent.value else { return }
            // Removal happens while SwiftUI is updating views, when the page can't change
            // state yet.
            let onCommit = parent.onCommit
            DispatchQueue.main.async { onCommit(value) }
        }
    }
}

/// Commits its text before leaving the window: switching Settings pages removes the field
/// without taking focus, which would otherwise drop what was typed.
private final class CommitOnRemovalField: NSTextField {
    var onRemoval: (NSTextField) -> Void = { _ in }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            onRemoval(self)
            abortEditing()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
