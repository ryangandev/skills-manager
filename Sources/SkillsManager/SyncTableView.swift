import SkillsCore
import SwiftUI

/// Every skill against every agent, with a one-click way to fill the gaps.
struct SyncTableView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        Table(model.visibleSkills, selection: Binding(get: { model.selection }, set: { model.requestSelection($0) })) {
            TableColumn("Skill") { (skill: Skill) in
                HStack(spacing: 4) {
                    Text(skill.name).fontWeight(.semibold)
                    if skill.isBuiltin {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Read-only")
                    }
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn(Agent.claude.displayName) { (skill: Skill) in
                AgentCell(skill: skill, agent: .claude)
            }
            .width(min: 110, ideal: 130)

            TableColumn(Agent.codex.displayName) { (skill: Skill) in
                AgentCell(skill: skill, agent: .codex)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Status") { (skill: Skill) in
                StatusPill(status: skill.status)
            }
            .width(min: 110, ideal: 140)
        }
        .contextMenu(forSelectionType: Skill.ID.self) { ids in
            if let id = ids.first, let skill = model.skill(id: id) {
                SkillContextMenu(skill: skill)
            }
        } primaryAction: { ids in
            // Double-click shows the skill's details in the library.
            guard let id = ids.first else { return }
            model.filter = .all
            model.selection = id
        }
    }
}

private struct AgentCell: View {
    @Environment(LibraryModel.self) private var model
    let skill: Skill
    let agent: Agent

    var body: some View {
        if let install = skill.install(for: agent) {
            Label(install.isBuiltin ? "Built in" : install.isSymlink ? "Linked" : "Installed", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.okText)
                .fontWeight(.medium)
        } else if skill.isBuiltin {
            Text("Not installed").foregroundStyle(.secondary)
        } else {
            // Table cells drop button chrome by default, which makes the action look like plain text.
            Button("Install…") { model.sheet = .install(skill, into: agent) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
