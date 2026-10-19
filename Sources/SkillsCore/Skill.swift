import Foundation

/// One copy of a skill inside one agent's skills folder.
public struct SkillInstall: Sendable, Hashable, Identifiable {
    public var agent: Agent
    /// The entry in the agent's folder (possibly a symlink).
    public var folderURL: URL
    /// Where the files really live once symlinks are followed.
    public var resolvedURL: URL
    public var isSymlink: Bool
    public var isBuiltin: Bool
    /// A digest of every file in the folder, used to tell identical copies apart from diverged ones.
    public var contentHash: String

    public var id: String { folderURL.path }

    public var skillFileURL: URL { resolvedURL.appendingPathComponent("SKILL.md") }

    public init(agent: Agent, folderURL: URL, resolvedURL: URL, isSymlink: Bool, isBuiltin: Bool, contentHash: String) {
        self.agent = agent
        self.folderURL = folderURL
        self.resolvedURL = resolvedURL
        self.isSymlink = isSymlink
        self.isBuiltin = isBuiltin
        self.contentHash = contentHash
    }
}

public struct SkillFile: Sendable, Hashable, Identifiable {
    public var relativePath: String
    public var isDirectory: Bool
    public var size: Int64

    public var id: String { relativePath }
    public var name: String { (relativePath as NSString).lastPathComponent }
    public var depth: Int { relativePath.split(separator: "/").count - 1 }

    public init(relativePath: String, isDirectory: Bool, size: Int64) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.size = size
    }

    /// Files the in-app editor can open as text.
    public var isEditableText: Bool {
        guard !isDirectory, size < 2_000_000 else { return false }
        let ext = (relativePath as NSString).pathExtension.lowercased()
        return ["md", "markdown", "txt", "yaml", "yml", "json", "toml", "py", "sh", "js", "ts", "rb", "swift", ""].contains(ext)
    }
}

/// How a skill's copies relate across agents.
public enum SyncStatus: Sendable, Hashable {
    /// Every agent points at the same folder through symlinks.
    case linked
    /// Separate copies with byte-identical files.
    case identical
    /// Separate copies whose files have drifted apart.
    case differs
    /// Installed in a single agent.
    case only(Agent)
    /// Shipped with the agent and read-only.
    case builtin(Agent)

    public var isShared: Bool {
        switch self {
        case .linked, .identical, .differs: true
        case .only, .builtin: false
        }
    }
}

/// A skill, grouped across every agent that has it.
public struct Skill: Sendable, Hashable, Identifiable {
    public var id: String
    public var folderName: String
    public var installs: [SkillInstall]
    public var document: SkillDocument
    public var files: [SkillFile]

    public init(id: String, folderName: String, installs: [SkillInstall], document: SkillDocument, files: [SkillFile]) {
        self.id = id
        self.folderName = folderName
        self.installs = installs.sorted { $0.agent < $1.agent }
        self.document = document
        self.files = files
    }

    public var name: String { document.name ?? folderName }
    public var summary: String { document.description ?? "" }
    public var isBuiltin: Bool { installs.contains(where: \.isBuiltin) }
    public var agents: [Agent] { installs.map(\.agent) }

    public func install(for agent: Agent) -> SkillInstall? {
        installs.first { $0.agent == agent }
    }

    /// The copy edits start from: a real folder rather than a link when there is one.
    public var primaryInstall: SkillInstall {
        installs.first(where: { !$0.isSymlink }) ?? installs[0]
    }

    /// The distinct folders on disk; symlinked copies collapse into one.
    public var distinctFolders: [URL] {
        var seen = Set<String>()
        return installs.compactMap { install in
            seen.insert(install.resolvedURL.standardizedFileURL.path).inserted ? install.resolvedURL : nil
        }
    }

    public var status: SyncStatus {
        if let builtin = installs.first(where: \.isBuiltin) { return .builtin(builtin.agent) }
        if installs.count == 1 { return .only(installs[0].agent) }
        if distinctFolders.count == 1 { return .linked }
        let hashes = Set(installs.map(\.contentHash))
        return hashes.count == 1 ? .identical : .differs
    }
}
