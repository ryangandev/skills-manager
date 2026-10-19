import SkillsCore
import SwiftUI

struct SkillListView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        let skills = model.visibleSkills

        ScrollViewReader { proxy in
            List(selection: selectionBinding) {
                ForEach(skills) { skill in
                    SkillRow(skill: skill)
                        .contextMenu { SkillContextMenu(skill: skill) }
                        .tag(skill.id)
                }
            }
            // Selection can come from elsewhere (the sync table, a new skill), so bring it into view.
            .onAppear {
                // A freshly created list has no rows laid out yet, so wait one run loop turn.
                DispatchQueue.main.async { scrollToSelection(proxy) }
            }
            .onChange(of: model.selection) { scrollToSelection(proxy) }
        }
        .overlay {
            if model.hasLoaded && skills.isEmpty {
                if model.search.isEmpty {
                    ContentUnavailableView("No Skills Here", systemImage: "tray", description: Text("Nothing matches \(model.filter.title)."))
                } else {
                    ContentUnavailableView.search(text: model.search)
                }
            }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = model.selection else { return }
        proxy.scrollTo(id)
    }

    private var selectionBinding: Binding<Skill.ID?> {
        Binding(get: { model.selection }, set: { model.requestSelection($0) })
    }
}

struct SkillRow: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(skill.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if skill.isBuiltin {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Read-only")
                }
                Spacer(minLength: 0)
                if skill.status == .differs {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.warningText)
                        .accessibilityLabel("Copies differ")
                }
            }
            if !skill.summary.isEmpty {
                Text(skill.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                ForEach(skill.agents, id: \.self) { AgentBadge(agent: $0) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SkillContextMenu: View {
    @Environment(LibraryModel.self) private var model
    let skill: Skill

    var body: some View {
        if skill.isBuiltin {
            Button("Duplicate to Edit…") { model.sheet = .newSkill(duplicating: skill) }
        } else {
            Button("Edit") { model.beginEditing(skill) }
            Button("Duplicate…") { model.sheet = .newSkill(duplicating: skill) }
        }
        ForEach(Agent.allCases.filter { skill.install(for: $0) == nil }) { agent in
            Button("Install in \(agent.displayName)…") { model.sheet = .install(skill, into: agent) }
        }
        Divider()
        Button("Reveal in Finder") { model.reveal(skill.primaryInstall.folderURL) }
    }
}
