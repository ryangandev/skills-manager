import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    private enum SourceKind: Hashable {
        case github, local
    }

    private enum Phase: Equatable {
        case idle
        case working(String)
        case failed(String)
        case ready
    }

    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SourceKind = .github
    @State private var urlText = ""
    @State private var phase: Phase = .idle
    @State private var candidates: [ImportCandidate] = []
    @State private var selected: Set<ImportCandidate.ID> = []
    @State private var agents: Set<Agent> = Set(Agent.allCases)
    @State private var method: InstallMethod = .symlink
    @State private var remember = true
    @State private var originLabel = ""
    @State private var workspace: URL?
    @State private var showingPicker = false
    @State private var dropTargeted = false
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SheetHeader(title: "Import Skills", subtitle: "Scan a source for SKILL.md files and pick which ones to install.")
                Spacer()
                Picker("Source", selection: $kind) {
                    Text("GitHub").tag(SourceKind.github)
                    Text("Folder or ZIP").tag(SourceKind.local)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if kind == .github {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Repository or folder URL")
                    HStack {
                        TextField("https://github.com/owner/repo", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .onSubmit(scanGitHub)
                        Button(phase == .ready ? "Rescan" : "Scan", action: scanGitHub)
                            .disabled(GitHubSource(urlText) == nil || isWorking)
                    }
                    Text("Public repositories. A /tree/<branch>/<folder> link narrows the scan to that folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            dropZone

            statusArea

            if !candidates.isEmpty {
                candidateList
                HStack(spacing: 14) {
                    Text("Install in").font(.callout.weight(.semibold))
                    ForEach(Agent.allCases) { agent in
                        Toggle(agent.displayName, isOn: binding(for: agent))
                            .toggleStyle(.checkbox)
                    }
                    if agents.count > 1 {
                        Picker("Second agent", selection: $method) {
                            Text("Linked").tag(InstallMethod.symlink)
                            Text("Copied").tag(InstallMethod.copy)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("How the second agent gets each skill")
                    }
                }
                .font(.callout)
                Toggle("Remember where these skills came from", isOn: $remember)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(importTitle, action: importSelected)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(importable.isEmpty || isWorking)
            }
        }
        .padding(24)
        .frame(width: 620)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder, .zip]) { result in
            if case .success(let url) = result { scanLocal(url) }
        }
        .onDisappear {
            scanTask?.cancel()
            cleanUp()
        }
    }

    // MARK: Pieces

    private var dropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
            Text("Drop a skill folder or .zip file here, or")
            Button("Choose…") { showingPicker = true }
                .buttonStyle(.link)
        }
        .font(.callout)
        .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, kind == .local && candidates.isEmpty ? 34 : 14)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(dropTargeted ? Color.accentColor : Color(nsColor: .tertiaryLabelColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            kind = .local
            scanLocal(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .working(let message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
            .font(.callout)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.warningText)
        case .ready:
            Text("\(originLabel) · \(candidates.count == 1 ? "1 skill" : "\(candidates.count) skills") found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var candidateList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle("Select all", isOn: allBinding)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Text("Skill")
                Spacer()
                Text("Will install in").frame(width: 170, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.4))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func candidateRow(_ candidate: ImportCandidate) -> some View {
        let plan = plan(for: candidate)
        return HStack(alignment: .top, spacing: 10) {
            Toggle(candidate.name, isOn: rowBinding(candidate))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(plan.targets.isEmpty)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.installName)
                    .font(.callout.monospaced().weight(.semibold))
                if !candidate.summary.isEmpty {
                    Text(candidate.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if candidate.relativePath != candidate.folderName {
                    Text(candidate.relativePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                ForEach(plan.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.warningText)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if plan.targets.isEmpty {
                    Text("Nothing to install").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(plan.targets, id: \.self) { AgentBadge(agent: $0) }
            }
            .frame(width: 170, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(plan.notes.isEmpty ? Color.clear : Color.warningText.opacity(0.05))
    }

    // MARK: Planning

    private struct Plan {
        var targets: [Agent]
        var notes: [String]
    }

    /// Which of the chosen agents a candidate can go into, and why any are skipped.
    private func plan(for candidate: ImportCandidate) -> Plan {
        var targets: [Agent] = []
        var notes: [String] = []
        if !SkillValidator.nameIssues(candidate.installName).isEmpty {
            return Plan(targets: [], notes: ["“\(candidate.installName)” is not a valid skill name"])
        }
        for agent in agents.sorted() {
            if model.skill(id: "\(agent.rawValue)-builtin/\(candidate.installName)") != nil {
                notes.append("\(agent.displayName) already has a built-in \(candidate.installName). Skipped there.")
            } else if model.operations.exists(candidate.installName, in: agent) {
                notes.append("Already in \(agent.displayName). Skipped there.")
            } else {
                targets.append(agent)
            }
        }
        return Plan(targets: targets, notes: notes)
    }

    private var importable: [ImportCandidate] {
        candidates.filter { selected.contains($0.id) && !plan(for: $0).targets.isEmpty }
    }

    private var importTitle: String {
        switch importable.count {
        case 0: "Import"
        case 1: "Import 1 Skill"
        default: "Import \(importable.count) Skills"
        }
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    // MARK: Bindings

    private func binding(for agent: Agent) -> Binding<Bool> {
        Binding(
            get: { agents.contains(agent) },
            set: { isOn in
                if isOn { agents.insert(agent) } else if agents.count > 1 { agents.remove(agent) }
            }
        )
    }

    private func rowBinding(_ candidate: ImportCandidate) -> Binding<Bool> {
        Binding(
            get: { selected.contains(candidate.id) },
            set: { isOn in
                if isOn { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
            }
        )
    }

    private var allBinding: Binding<Bool> {
        Binding(
            get: { !candidates.isEmpty && candidates.allSatisfy { selected.contains($0.id) } },
            set: { isOn in selected = isOn ? Set(candidates.map(\.id)) : [] }
        )
    }

    // MARK: Scanning

    private func scanGitHub() {
        guard let source = GitHubSource(urlText), !isWorking else { return }
        begin("Downloading \(source.displayName)…", origin: source.displayName)
        scanTask = Task {
            do {
                let workspace = try newWorkspace()
                let root = try await Task.detached { try await SkillImporter.download(source, into: workspace) }.value
                await finishScan(root)
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func scanLocal(_ url: URL) {
        guard !isWorking else { return }
        begin("Scanning \(url.lastPathComponent)…", origin: url.abbreviatedPath)
        scanTask = Task {
            do {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    await finishScan(url)
                } else {
                    let workspace = try newWorkspace()
                    try await Task.detached { try SkillImporter.extractZip(url, to: workspace) }.value
                    await finishScan(workspace)
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func begin(_ message: String, origin: String) {
        candidates = []
        selected = []
        originLabel = origin
        phase = .working(message)
    }

    private func finishScan(_ root: URL) async {
        let found = await Task.detached { SkillImporter.findSkills(in: root) }.value
        guard !Task.isCancelled else { return }
        candidates = found
        selected = Set(found.filter { !plan(for: $0).targets.isEmpty }.map(\.id))
        phase = found.isEmpty ? .failed(SkillImportError.nothingFound.localizedDescription) : .ready
    }

    private func newWorkspace() throws -> URL {
        cleanUp()
        let url = try SkillImporter.makeWorkspace()
        workspace = url
        return url
    }

    private func cleanUp() {
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
            self.workspace = nil
        }
    }

    // MARK: Importing

    private func importSelected() {
        var imported: [String] = []
        var failures: [String] = []
        for candidate in importable {
            let targets = plan(for: candidate).targets
            do {
                try model.operations.importFolder(candidate.folderURL, named: candidate.installName, into: targets, method: method)
                imported.append(candidate.installName)
            } catch {
                failures.append("\(candidate.installName): \(error.localizedDescription)")
            }
        }
        if remember, !imported.isEmpty {
            try? model.sourceStore.record(originLabel, for: imported)
        }
        model.reload()
        if failures.isEmpty {
            dismiss()
        } else {
            candidates.removeAll { imported.contains($0.installName) }
            phase = .failed(failures.joined(separator: "\n"))
        }
    }
}
