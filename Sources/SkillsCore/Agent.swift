import Foundation

/// A coding agent whose skills this app manages.
public enum Agent: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public static func < (lhs: Agent, rhs: Agent) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Where each agent keeps its skills on disk.
///
/// Claude Code honours `CLAUDE_CONFIG_DIR` and Codex honours `CODEX_HOME`;
/// both fall back to a dot folder in the home directory.
public struct AgentLocations: Sendable, Equatable {
    public var claudeHome: URL
    public var codexHome: URL

    public init(claudeHome: URL, codexHome: URL) {
        self.claudeHome = claudeHome
        self.codexHome = codexHome
    }

    /// Locations rooted in a single home directory, used by tests.
    public init(home: URL) {
        self.init(
            claudeHome: home.appendingPathComponent(".claude", isDirectory: true),
            codexHome: home.appendingPathComponent(".codex", isDirectory: true)
        )
    }

    public static var current: AgentLocations {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        func dir(_ key: String, fallback: String) -> URL {
            if let value = env[key], !value.isEmpty {
                return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
            }
            return home.appendingPathComponent(fallback, isDirectory: true)
        }
        return AgentLocations(
            claudeHome: dir("CLAUDE_CONFIG_DIR", fallback: ".claude"),
            codexHome: dir("CODEX_HOME", fallback: ".codex")
        )
    }

    /// The folder holding the user's own skills for an agent.
    public func skillsRoot(for agent: Agent) -> URL {
        switch agent {
        case .claude: claudeHome.appendingPathComponent("skills", isDirectory: true)
        case .codex: codexHome.appendingPathComponent("skills", isDirectory: true)
        }
    }

    /// The folder holding skills that ship with the agent, if it has one.
    public func builtinRoot(for agent: Agent) -> URL? {
        switch agent {
        case .claude: nil
        case .codex: skillsRoot(for: .codex).appendingPathComponent(".system", isDirectory: true)
        }
    }

    /// Every folder worth watching for changes.
    public var watchedRoots: [URL] {
        Agent.allCases.map { skillsRoot(for: $0) }
    }
}

extension URL {
    /// The path with the home directory shortened to `~`.
    public var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
