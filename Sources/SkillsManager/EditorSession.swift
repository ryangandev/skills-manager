import Foundation
import Observation
import SkillsCore

/// Unsaved edits to one skill: the SKILL.md form fields plus any other text files.
@Observable
final class EditorSession: Identifiable {
    static let skillFile = "SKILL.md"

    let id = UUID()
    private(set) var skill: Skill
    private let operations: SkillOperations

    /// The copy the edits started from.
    private(set) var sourceAgent: Agent
    var selectedPath = EditorSession.skillFile {
        didSet { ensureLoaded(selectedPath) }
    }
    /// Write to every copy rather than only the source copy.
    var saveToAll: Bool
    /// A selection the user made while there were unsaved changes; set means "ask first".
    var pendingSelection: Skill.ID??
    var pendingClose = false

    private var baseDocument = SkillDocument()
    private var originalDescription = ""
    private var originalBody = ""
    var descriptionDraft = ""
    var bodyDraft = ""
    private var originalTexts: [String: String] = [:]
    private var texts: [String: String] = [:]

    init(skill: Skill, operations: SkillOperations) {
        self.skill = skill
        self.operations = operations
        self.sourceAgent = skill.primaryInstall.agent
        self.saveToAll = skill.status != .differs
        load()
    }

    var sourceFolder: URL {
        (skill.install(for: sourceAgent) ?? skill.primaryInstall).resolvedURL
    }

    /// Text files the editor can open, SKILL.md first.
    var editableFiles: [SkillFile] {
        skill.files.filter(\.isEditableText)
    }

    var hasSeparateCopies: Bool { skill.distinctFolders.count > 1 }

    var targetFolders: [URL] {
        saveToAll ? skill.distinctFolders : [sourceFolder]
    }

    var targetAgents: [Agent] {
        let targets = Set(targetFolders.map { $0.standardizedFileURL.path })
        return skill.installs.filter { targets.contains($0.resolvedURL.standardizedFileURL.path) }.map(\.agent)
    }

    // MARK: Loading

    private func load() {
        let text = (try? String(contentsOf: sourceFolder.appendingPathComponent(Self.skillFile), encoding: .utf8)) ?? ""
        baseDocument = SkillDocument.parse(text)
        originalDescription = baseDocument.description ?? ""
        originalBody = baseDocument.body
        descriptionDraft = originalDescription
        bodyDraft = originalBody
        originalTexts = [:]
        texts = [:]
        selectedPath = Self.skillFile
    }

    func switchSource(to agent: Agent) {
        guard !isDirty, skill.install(for: agent) != nil else { return }
        sourceAgent = agent
        load()
    }

    /// Keeps the install list current after a rescan without touching the drafts.
    func update(skill fresh: Skill) {
        skill = fresh
        if fresh.install(for: sourceAgent) == nil {
            sourceAgent = fresh.primaryInstall.agent
        }
    }

    /// Reads a file into the drafts the first time it is opened.
    func ensureLoaded(_ path: String) {
        guard path != Self.skillFile, texts[path] == nil else { return }
        let text = (try? String(contentsOf: sourceFolder.appendingPathComponent(path), encoding: .utf8)) ?? ""
        originalTexts[path] = text
        texts[path] = text
    }

    func text(for path: String) -> String {
        texts[path] ?? ""
    }

    func setText(_ text: String, for path: String) {
        ensureLoaded(path)
        texts[path] = text
    }

    // MARK: State

    var isSkillFileDirty: Bool {
        descriptionDraft != originalDescription || bodyDraft != originalBody
    }

    var dirtyPaths: [String] {
        var paths = texts.keys.filter { texts[$0] != originalTexts[$0] }.sorted()
        if isSkillFileDirty { paths.insert(Self.skillFile, at: 0) }
        return paths
    }

    var isDirty: Bool { !dirtyPaths.isEmpty }

    func isDirty(_ path: String) -> Bool {
        path == Self.skillFile ? isSkillFileDirty : texts[path] != originalTexts[path] && texts[path] != nil
    }

    var currentDocument: SkillDocument {
        var document = baseDocument
        if descriptionDraft != originalDescription {
            document.setValue(descriptionDraft, for: "description")
        }
        document.body = bodyDraft
        return document
    }

    var issues: [SkillIssue] {
        SkillValidator.issues(for: currentDocument, folderName: skill.folderName)
    }

    var hasErrors: Bool { issues.contains { $0.severity == .error } }

    // MARK: Actions

    func save() throws {
        let folders = targetFolders
        for path in dirtyPaths {
            let text = path == Self.skillFile ? currentDocument.serialized() : texts[path] ?? ""
            try operations.write(text, relativePath: path, to: folders)
        }
        let saved = currentDocument
        baseDocument = saved
        originalDescription = saved.description ?? ""
        originalBody = saved.body
        descriptionDraft = originalDescription
        for (path, text) in texts { originalTexts[path] = text }
    }

    func revert() {
        descriptionDraft = originalDescription
        bodyDraft = originalBody
        texts = originalTexts
    }
}
