import SkillsCore
import SwiftUI

struct SkillEditorView: View {
    @Environment(LibraryModel.self) private var model
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            if session.hasSeparateCopies {
                CopiesBanner(session: session)
                Divider()
            }
            HStack(spacing: 0) {
                fileList
                    .frame(width: 210)
                Divider()
                editorPane
                    .frame(minWidth: 360, maxWidth: .infinity)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        previewSection
                        if session.selectedPath == EditorSession.skillFile {
                            ChecksSection(issues: session.issues, session: session)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)
                .background(.background.secondary)
            }
        }
        .navigationTitle(session.skill.name)
        .navigationSubtitle(session.isDirty ? "Edited" : session.selectedPath)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { close() } label: {
                    Label("Back to Library", systemImage: "chevron.backward")
                }
                .help("Back to the library")
                .keyboardShortcut(.escape, modifiers: [])
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert") { session.revert() }
                    .disabled(!session.isDirty)
                Button(saveTitle) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s")
                    .disabled(!session.isDirty || session.hasErrors)
                    .help(session.hasErrors ? "Fix the errors under Checks first" : "Save (⌘S)")
            }
        }
        .confirmationDialog(
            "Discard unsaved changes to \(session.skill.name)?",
            isPresented: discardBinding
        ) {
            Button("Discard Changes", role: .destructive) { discardAndContinue() }
            Button("Keep Editing", role: .cancel) {
                session.pendingSelection = nil
                session.pendingClose = false
            }
        }
    }

    private var saveTitle: String {
        session.saveToAll && session.hasSeparateCopies ? "Save to Both Agents" : "Save"
    }

    // MARK: File list

    private var fileList: some View {
        List(selection: $session.selectedPath) {
            Section(session.skill.folderName) {
                ForEach(session.editableFiles) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(file.relativePath)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if session.isDirty(file.relativePath) {
                            Circle()
                                .fill(Color.warningText)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel("Edited")
                        }
                    }
                    .tag(file.relativePath)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Editing

    @ViewBuilder
    private var editorPane: some View {
        if session.selectedPath == EditorSession.skillFile {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.callout.weight(.semibold))
                        Text(session.skill.folderName)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Text("Matches the folder name. To rename, duplicate the skill under a new name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Description").font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(session.descriptionDraft.count) / \(SkillValidator.maxDescriptionLength)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(session.descriptionDraft.count > SkillValidator.maxDescriptionLength ? Color.warningText : .secondary)
                        }
                        TextEditor(text: $session.descriptionDraft)
                            .font(.body)
                            .frame(height: 84)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                            .accessibilityLabel("Description")
                        Text("Agents read this to decide when to load the skill. Say what it does and when to use it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !session.currentDocument.otherKeys.isEmpty {
                        Text("Other frontmatter keys are kept as they are: \(session.currentDocument.otherKeys.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                Divider()
                Text("Instructions (Markdown)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                CodeEditor(text: $session.bodyDraft)
            }
        } else {
            CodeEditor(text: Binding(
                get: { session.text(for: session.selectedPath) },
                set: { session.setText($0, for: session.selectedPath) }
            ))
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewSection: some View {
        let path = session.selectedPath
        let isMarkdown = ["md", "markdown"].contains((path as NSString).pathExtension.lowercased())
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if path == EditorSession.skillFile {
                MarkdownPreview(markdown: session.bodyDraft)
            } else if isMarkdown {
                MarkdownPreview(markdown: session.text(for: path))
            } else {
                Text("No preview for this file type.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private var discardBinding: Binding<Bool> {
        Binding(
            get: { session.pendingSelection != nil || session.pendingClose },
            set: { if !$0 { session.pendingSelection = nil; session.pendingClose = false } }
        )
    }

    private func save() {
        do {
            try session.save()
        } catch {
            model.errorMessage = error.localizedDescription
        }
        model.reload()
    }

    private func close() {
        if session.isDirty {
            session.pendingClose = true
        } else {
            model.editor = nil
        }
    }

    private func discardAndContinue() {
        let pending = session.pendingSelection
        model.editor = nil
        if let pending {
            model.selection = pending
        }
    }
}

/// A plain monospaced text editor for Markdown and other text files.
private struct CodeEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.background)
            .autocorrectionDisabled()
    }
}

private struct CopiesBanner: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.skill.status == .differs ? "exclamationmark.triangle.fill" : "arrow.left.arrow.right")
                .foregroundStyle(session.skill.status == .differs ? Color.warningText : Color.accentColor)
            if session.skill.status == .differs {
                Text("The copies differ. Editing the")
                Picker("Copy", selection: Binding(get: { session.sourceAgent }, set: { session.switchSource(to: $0) })) {
                    ForEach(session.skill.agents, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(session.isDirty)
                Text("copy.")
                Spacer(minLength: 8)
                Toggle("Overwrite the other copy on save", isOn: $session.saveToAll)
            } else {
                Text("Identical copies in \(session.skill.agents.map(\.displayName).joined(separator: " and ")). \(session.saveToAll ? "Saving writes both." : "Saving writes only the \(session.sourceAgent.displayName) copy.")")
                Spacer(minLength: 8)
                Toggle("Save to both", isOn: $session.saveToAll)
            }
        }
        .font(.callout)
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.07))
    }
}

private struct ChecksSection: View {
    let issues: [SkillIssue]
    let session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if issues.isEmpty {
                check(ok: true, title: "Frontmatter is valid", detail: "name and description are set")
                check(ok: true, title: "Description length", detail: "\(session.descriptionDraft.count) of \(SkillValidator.maxDescriptionLength) characters")
            }
            ForEach(issues) { issue in
                check(ok: false, title: issue.title, detail: issue.detail, error: issue.severity == .error)
            }
            if session.isDirty {
                check(ok: true, title: "Will save to", detail: session.targetAgents.map(\.displayName).joined(separator: " and "))
            }
        }
    }

    private func check(ok: Bool, title: String, detail: String, error: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : error ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.okText : error ? Color.red : Color.warningText)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
