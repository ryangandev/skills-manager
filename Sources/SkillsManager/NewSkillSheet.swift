import SkillsCore
import SwiftUI

struct NewSkillSheet: View {
    private enum Start: Hashable {
        case blank, withResources, duplicate
    }

    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var start: Start
    @State private var duplicateID: Skill.ID?
    @State private var agents: Set<Agent>
    @State private var method: InstallMethod = .symlink
    @FocusState private var nameFocused: Bool

    init(duplicating source: Skill?) {
        _name = State(initialValue: source.map { "\($0.folderName)-copy" } ?? "")
        _description = State(initialValue: source?.summary ?? "")
        _start = State(initialValue: source == nil ? .blank : .duplicate)
        _duplicateID = State(initialValue: source?.id)
        _agents = State(initialValue: source?.isBuiltin == true ? Set(source!.agents) : Set(Agent.allCases))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "New Skill", subtitle: "Creates a folder with a SKILL.md, then opens it in the editor.")

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Name")
                TextField("release-notes", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($nameFocused)
                    .onSubmit(create)
                nameStatus
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    FieldLabel("Description")
                    Spacer()
                    Text("\(description.count) / \(SkillValidator.maxDescriptionLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(description.count > SkillValidator.maxDescriptionLength ? Color.warningText : .secondary)
                }
                TextEditor(text: $description)
                    .font(.body)
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("What the skill does, and when the agent should use it.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    .accessibilityLabel("Description")
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Start from")
                HStack(alignment: .top, spacing: 8) {
                    ChoiceCard(title: "Blank", detail: "Frontmatter and an empty body", isSelected: start == .blank) { start = .blank }
                    ChoiceCard(title: "With folders", detail: "Adds scripts, references and assets", isSelected: start == .withResources) { start = .withResources }
                    ChoiceCard(title: "Duplicate", detail: "Copy an existing skill", isSelected: start == .duplicate) {
                        start = .duplicate
                        if duplicateID == nil { duplicateID = model.skills.first?.id }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if start == .duplicate {
                    Picker("Copy from", selection: $duplicateID) {
                        ForEach(model.skills) { skill in
                            Text(skill.name).tag(Optional(skill.id))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Install in")
                VStack(spacing: 0) {
                    ForEach(Array(Agent.allCases.enumerated()), id: \.element) { index, agent in
                        if index > 0 { Divider() }
                        Toggle(isOn: binding(for: agent)) {
                            HStack(spacing: 8) {
                                AgentDot(agent: agent)
                                Text(agent.displayName).fontWeight(.medium)
                                Spacer()
                                Text(agentDetail(agent))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                if agents.count > 1 {
                    Picker("Second agent", selection: $method) {
                        Text("Link to the \(sortedAgents[0].displayName) copy").tag(InstallMethod.symlink)
                        Text("Separate copy").tag(InstallMethod.copy)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .font(.callout)
                }
            }

            HStack {
                Button("Reveal Skills Folder") {
                    model.reveal(model.locations.skillsRoot(for: sortedAgents.first ?? .claude))
                }
                .buttonStyle(.link)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create and Edit", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onAppear { nameFocused = true }
    }

    private var sortedAgents: [Agent] { agents.sorted() }

    private var nameIssues: [String] {
        guard !name.isEmpty else { return [] }
        var issues = SkillValidator.nameIssues(name).map(\.title)
        for agent in sortedAgents where model.operations.exists(name, in: agent) {
            issues.append("\(agent.displayName) already has a skill named \(name)")
        }
        return issues
    }

    @ViewBuilder
    private var nameStatus: some View {
        if name.isEmpty {
            Text("Lowercase letters, numbers and hyphens. This is also the folder name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let issue = nameIssues.first {
            Label(issue, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Label("Available in \(sortedAgents.map(\.displayName).joined(separator: " and "))", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(Color.okText)
        }
    }

    private var canCreate: Bool {
        !name.isEmpty && nameIssues.isEmpty && !agents.isEmpty
            && SkillValidator.descriptionIssues(description).isEmpty
            && (start != .duplicate || duplicateID != nil)
    }

    private func agentDetail(_ agent: Agent) -> String {
        if agents.count > 1, agent != sortedAgents.first, agents.contains(agent) {
            return method == .symlink ? "Linked to the \(sortedAgents[0].displayName) copy" : "Separate copy"
        }
        return model.operations.destination(for: name.isEmpty ? "…" : name, in: agent).abbreviatedPath
    }

    private func binding(for agent: Agent) -> Binding<Bool> {
        Binding(
            get: { agents.contains(agent) },
            set: { isOn in
                if isOn { agents.insert(agent) } else if agents.count > 1 { agents.remove(agent) }
            }
        )
    }

    private func create() {
        guard canCreate else { return }
        let template: SkillTemplate
        switch start {
        case .blank: template = .blank
        case .withResources: template = .withResources
        case .duplicate:
            guard let id = duplicateID, let source = model.skill(id: id) else { return }
            template = .duplicate(of: source.primaryInstall.resolvedURL)
        }
        do {
            try model.operations.create(
                name: name,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                template: template,
                agents: sortedAgents,
                method: method
            )
        } catch {
            model.errorMessage = error.localizedDescription
            return
        }
        let id = name
        dismiss()
        Task { await model.select(andEdit: id) }
    }
}
