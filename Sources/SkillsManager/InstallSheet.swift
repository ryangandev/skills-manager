import SkillsCore
import SwiftUI

/// Puts an existing skill into another agent, by link or copy.
struct InstallSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let skill: Skill
    let agent: Agent
    @State private var method: InstallMethod = .symlink

    var body: some View {
        let source = skill.primaryInstall
        let destination = model.operations.destination(for: skill.folderName, in: agent)
        let destinationFree = !model.operations.exists(skill.folderName, in: agent)
        let documentOK = !SkillValidator.issues(for: skill.document, folderName: skill.folderName).contains { $0.severity == .error }
        let extraFiles = skill.files.filter { !$0.isDirectory && $0.relativePath != "SKILL.md" }

        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(
                title: "Install “\(skill.name)” in \(agent.displayName)",
                subtitle: "From \(source.resolvedURL.abbreviatedPath)"
            )

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("How to install")
                // A built-in skill can be replaced by its agent at any time, so only copies make sense.
                MethodPicker(method: $method, primaryAgent: source.agent, allowsLink: !skill.isBuiltin)
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Destination")
                Text(destination.abbreviatedPath)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Checks")
                CheckRow(ok: documentOK, text: documentOK ? "SKILL.md has a valid name and description" : "SKILL.md has problems; fix them in the editor first")
                CheckRow(ok: destinationFree, text: destinationFree ? "No skill named \(skill.folderName) in \(agent.displayName) yet" : "\(agent.displayName) already has a \(skill.folderName) folder")
                if !extraFiles.isEmpty {
                    CheckRow(ok: true, text: extraFiles.count == 1 ? "\(extraFiles[0].relativePath) comes along with SKILL.md" : "\(extraFiles.count) more files come along with SKILL.md")
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Install") {
                    let chosen = skill.isBuiltin ? InstallMethod.copy : method
                    model.perform {
                        try model.operations.install(folder: source.resolvedURL, named: skill.folderName, into: agent, method: chosen)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!destinationFree || !documentOK)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
