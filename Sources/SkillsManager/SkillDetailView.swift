import SkillsCore
import SwiftUI

struct SkillDetailView: View {
    @Environment(LibraryModel.self) private var model
    let skill: Skill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !skill.summary.isEmpty {
                    Text(skill.summary)
                        .font(.title3.weight(.regular))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: 680, alignment: .leading)
                }
                if skill.isBuiltin {
                    Label("Ships with Codex in ~/.codex/skills/.system. Codex may replace it when it updates, so changes go into a copy.", systemImage: "lock.fill")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                if skill.status == .differs {
                    Label("The copies have drifted apart. Open the editor on the copy you want to keep, then save it to both agents.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.warningText)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.warningText.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                InstalledInSection(skill: skill)
                HStack(alignment: .top, spacing: 20) {
                    FilesSection(skill: skill)
                        .frame(minWidth: 220, maxWidth: 320)
                    FrontmatterSection(document: skill.document)
                }
                if !skill.document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Instructions")
                        MarkdownPreview(markdown: skill.document.body)
                            .padding(16)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text(sourceLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Reveal in Finder") { model.reveal(skill.primaryInstall.folderURL) }
            if skill.isBuiltin {
                Button("Duplicate to Edit…") { model.sheet = .newSkill(duplicating: skill) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Edit") { model.beginEditing(skill) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("e")
            }
        }
    }

    private var sourceLabel: String {
        var parts: [String] = []
        switch skill.status {
        case .builtin(let agent): parts.append("\(agent.displayName) built-in skill · read-only")
        case .linked: parts.append("Personal skill · one folder shared by both agents")
        case .identical: parts.append("Personal skill · identical copies in both agents")
        case .differs: parts.append("Personal skill · copies differ")
        case .only: parts.append("Personal skill")
        }
        if let source = model.importSources[skill.folderName], !skill.isBuiltin {
            parts.append("imported from \(source)")
        }
        return parts.joined(separator: " · ")
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.headline)
    }
}

private struct InstalledInSection: View {
    @Environment(LibraryModel.self) private var model
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Installed in")
            VStack(spacing: 0) {
                ForEach(Array(Agent.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { Divider() }
                    row(for: agent)
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        }
    }

    private func row(for agent: Agent) -> some View {
        let install = skill.install(for: agent)
        return HStack(spacing: 12) {
            AgentDot(agent: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName).fontWeight(.semibold)
                Text(path(for: agent, install: install))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            if let install {
                Label(stateLabel(install), systemImage: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.okText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.okText.opacity(0.12), in: Capsule())
                Menu {
                    Button("Reveal in Finder") { model.reveal(install.folderURL) }
                    if !install.isBuiltin {
                        Divider()
                        Button(install.isSymlink ? "Remove Link" : "Move to Trash", role: .destructive) {
                            model.remove(install)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for the \(agent.displayName) copy")
            } else if !skill.isBuiltin {
                Button("Install in \(agent.displayName)…") { model.sheet = .install(skill, into: agent) }
            } else {
                Text("Not installed").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func path(for agent: Agent, install: SkillInstall?) -> String {
        guard let install else { return model.operations.destination(for: skill.folderName, in: agent).abbreviatedPath }
        if install.isSymlink {
            return "\(install.folderURL.abbreviatedPath) → \(install.resolvedURL.abbreviatedPath)"
        }
        return install.folderURL.abbreviatedPath
    }

    private func stateLabel(_ install: SkillInstall) -> String {
        if install.isBuiltin { return "Built in" }
        if install.isSymlink { return "Linked" }
        switch skill.status {
        case .identical: return "Installed · identical"
        case .differs: return "Installed · differs"
        default: return "Installed"
        }
    }
}

private struct FilesSection: View {
    @Environment(LibraryModel.self) private var model
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Files")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(skill.files.prefix(60)) { file in
                    Button {
                        model.open(skill.primaryInstall.resolvedURL.appendingPathComponent(file.relativePath))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: file.isDirectory ? "folder" : "doc")
                                .foregroundStyle(file.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .frame(width: 16)
                            Text(file.name)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if !file.isDirectory {
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, CGFloat(file.depth) * 16)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(file.relativePath)")
                }
                if skill.files.count > 60 {
                    Text("\(skill.files.count - 60) more…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .padding(6)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        }
    }
}

private struct FrontmatterSection: View {
    let document: SkillDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("SKILL.md frontmatter")
            Text(document.hasFrontmatter ? (["---"] + document.entries.flatMap(\.lines) + ["---"]).joined(separator: "\n") : "No frontmatter")
                .font(.callout.monospaced())
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
