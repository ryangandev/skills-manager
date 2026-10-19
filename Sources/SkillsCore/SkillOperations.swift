import Foundation

public enum SkillOperationError: LocalizedError, Equatable {
    case destinationExists(URL)
    case invalidName(String)
    case missingSkillFile(URL)
    case unsafeLink(URL)
    case readOnly(String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let url):
            "Something already exists at \(url.abbreviatedPath)."
        case .invalidName(let name):
            "“\(name)” is not a valid skill name. Use lowercase letters, numbers and hyphens."
        case .missingSkillFile(let url):
            "No SKILL.md found in \(url.abbreviatedPath)."
        case .unsafeLink(let url):
            "The skill contains a link that points outside its folder: \(url.abbreviatedPath)."
        case .readOnly(let name):
            "\(name) ships with its agent and is read-only. Duplicate it to make changes."
        }
    }
}

/// How a skill reaches a second agent.
public enum InstallMethod: String, Sendable, CaseIterable, Identifiable {
    /// A symlink to the existing folder: one source of truth.
    case symlink
    /// An independent copy of the folder.
    case copy

    public var id: String { rawValue }
}

/// What a new skill starts with.
public enum SkillTemplate: Sendable, Hashable {
    case blank
    case withResources
    case duplicate(of: URL)
}

/// Every change the app makes on disk. Writes go through a staging folder or an
/// atomic file write, and removals go to the Trash, so nothing is lost halfway.
public struct SkillOperations: Sendable {
    public var locations: AgentLocations

    public init(locations: AgentLocations) {
        self.locations = locations
    }

    private var fm: FileManager { .default }

    public func destination(for name: String, in agent: Agent) -> URL {
        locations.skillsRoot(for: agent).appendingPathComponent(name, isDirectory: true)
    }

    public func exists(_ name: String, in agent: Agent) -> Bool {
        let url = destination(for: name, in: agent)
        return (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    // MARK: Installing

    /// Puts an existing folder into an agent's skills folder by link or copy.
    @discardableResult
    public func install(folder source: URL, named name: String, into agent: Agent, method: InstallMethod) throws -> URL {
        guard SkillValidator.nameIssues(name).isEmpty else { throw SkillOperationError.invalidName(name) }
        guard fm.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) else {
            throw SkillOperationError.missingSkillFile(source)
        }
        let destination = destination(for: name, in: agent)
        guard (try? fm.attributesOfItem(atPath: destination.path)) == nil else {
            throw SkillOperationError.destinationExists(destination)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        switch method {
        case .symlink:
            try fm.createSymbolicLink(at: destination, withDestinationURL: source.resolvingSymlinksInPath())
        case .copy:
            try copyFolder(source, to: destination)
        }
        return destination
    }

    /// Installs a folder that came from outside (an import) into several agents.
    /// The first agent gets a real copy; the rest link to it or copy it.
    @discardableResult
    public func importFolder(_ source: URL, named name: String, into agents: [Agent], method: InstallMethod) throws -> [URL] {
        try Self.assertNoEscapingLinks(in: source)
        let targets = agents.sorted()
        for agent in targets where exists(name, in: agent) {
            throw SkillOperationError.destinationExists(destination(for: name, in: agent))
        }
        guard let first = targets.first else { return [] }
        let primary = try install(folder: source, named: name, into: first, method: .copy)
        var created = [primary]
        for agent in targets.dropFirst() {
            created.append(try install(folder: primary, named: name, into: agent, method: method))
        }
        return created
    }

    private func copyFolder(_ source: URL, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source.resolvingSymlinksInPath(), to: staging)
        try fm.moveItem(at: staging, to: destination)
    }

    /// Rejects a folder holding symlinks that lead outside of it.
    public static func assertNoEscapingLinks(in root: URL) throws {
        let fm = FileManager.default
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { continue }
            let target = url.resolvingSymlinksInPath().standardizedFileURL.path
            if !(target == base || target.hasPrefix(base + "/")) {
                throw SkillOperationError.unsafeLink(url)
            }
        }
    }

    // MARK: Creating

    /// Creates a new skill. The first agent holds the folder; the others link to it or copy it.
    @discardableResult
    public func create(
        name: String,
        description: String,
        template: SkillTemplate,
        agents: [Agent],
        method: InstallMethod
    ) throws -> URL {
        guard SkillValidator.nameIssues(name).isEmpty else { throw SkillOperationError.invalidName(name) }
        let targets = agents.sorted()
        guard let first = targets.first else { throw SkillOperationError.invalidName(name) }
        for agent in targets where exists(name, in: agent) {
            throw SkillOperationError.destinationExists(destination(for: name, in: agent))
        }

        let root = locations.skillsRoot(for: first)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".\(name).staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        var document: SkillDocument
        switch template {
        case .blank, .withResources:
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            document = .template(name: name, description: description)
            if template == .withResources {
                for folder in ["scripts", "references", "assets"] {
                    try fm.createDirectory(at: staging.appendingPathComponent(folder), withIntermediateDirectories: true)
                }
            }
        case .duplicate(let source):
            try fm.copyItem(at: source.resolvingSymlinksInPath(), to: staging)
            let text = (try? String(contentsOf: staging.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
            document = SkillDocument.parse(text)
            document.setValue(name, for: "name")
            document.setValue(description, for: "description")
        }
        try document.serialized().write(to: staging.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let primary = destination(for: name, in: first)
        try fm.moveItem(at: staging, to: primary)
        for agent in targets.dropFirst() {
            try install(folder: primary, named: name, into: agent, method: method)
        }
        return primary
    }

    // MARK: Saving

    /// Writes a file into each folder. Symlinked copies share a folder and are written once.
    public func write(_ text: String, relativePath: String, to folders: [URL]) throws {
        var seen = Set<String>()
        for folder in folders {
            let resolved = folder.resolvingSymlinksInPath()
            guard seen.insert(resolved.standardizedFileURL.path).inserted else { continue }
            let file = resolved.appendingPathComponent(relativePath)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Removing

    /// Removes one agent's copy. A symlink is removed; a real folder goes to the Trash.
    public func remove(_ install: SkillInstall) throws {
        if install.isBuiltin { throw SkillOperationError.readOnly(install.folderURL.lastPathComponent) }
        if install.isSymlink {
            try fm.removeItem(at: install.folderURL)
        } else {
            try fm.trashItem(at: install.folderURL, resultingItemURL: nil)
        }
    }
}
