import CryptoKit
import Foundation

/// Reads every agent's skills folder and groups the copies by folder name.
public struct SkillScanner: Sendable {
    public var locations: AgentLocations

    public init(locations: AgentLocations) {
        self.locations = locations
    }

    public func scan() -> [Skill] {
        var grouped: [String: [SkillInstall]] = [:]
        var order: [String] = []

        for agent in Agent.allCases {
            for (install, key) in installs(for: agent) {
                if grouped[key] == nil { order.append(key) }
                grouped[key, default: []].append(install)
            }
        }

        return order.compactMap { key -> Skill? in
            guard let installs = grouped[key], !installs.isEmpty else { return nil }
            let folderName = installs[0].folderURL.lastPathComponent
            let probe = Skill(id: key, folderName: folderName, installs: installs, document: SkillDocument(), files: [])
            let primary = probe.primaryInstall
            let text = (try? String(contentsOf: primary.skillFileURL, encoding: .utf8)) ?? ""
            return Skill(
                id: key,
                folderName: folderName,
                installs: installs,
                document: SkillDocument.parse(text),
                files: Self.listFiles(in: primary.resolvedURL)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func installs(for agent: Agent) -> [(SkillInstall, String)] {
        var result: [(SkillInstall, String)] = []
        for folder in Self.skillFolders(in: locations.skillsRoot(for: agent)) {
            result.append((Self.makeInstall(agent: agent, folder: folder, builtin: false), folder.lastPathComponent))
        }
        if let builtinRoot = locations.builtinRoot(for: agent) {
            for folder in Self.skillFolders(in: builtinRoot) {
                let key = "\(agent.rawValue)-builtin/\(folder.lastPathComponent)"
                result.append((Self.makeInstall(agent: agent, folder: folder, builtin: true), key))
            }
        }
        return result
    }

    /// Direct children of `root` that are folders (or links to folders) holding a SKILL.md.
    static func skillFolders(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.filter { child in
            let resolved = child.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
            return fm.fileExists(atPath: resolved.appendingPathComponent("SKILL.md").path)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func makeInstall(agent: Agent, folder: URL, builtin: Bool) -> SkillInstall {
        let isSymlink = (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        let resolved = folder.resolvingSymlinksInPath()
        return SkillInstall(
            agent: agent,
            folderURL: folder,
            resolvedURL: resolved,
            isSymlink: isSymlink == true,
            isBuiltin: builtin,
            contentHash: contentHash(of: resolved)
        )
    }

    /// Every file and folder below `root`, depth first, hidden entries skipped.
    public static func listFiles(in root: URL, limit: Int = 500) -> [SkillFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let base = root.standardizedFileURL.path
        var files: [SkillFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            files.append(SkillFile(
                relativePath: String(path.dropFirst(base.count + 1)),
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0)
            ))
            if files.count >= limit { break }
        }
        return files.sorted { lhs, rhs in
            if lhs.relativePath == "SKILL.md" { return true }
            if rhs.relativePath == "SKILL.md" { return false }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    /// SHA-256 over the relative path and bytes of every regular file.
    public static func contentHash(of root: URL) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }
        let base = root.standardizedFileURL.path
        var entries: [(String, URL)] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.path
            entries.append((String(path.dropFirst(base.count)), url))
        }
        var hasher = SHA256()
        for (relative, url) in entries.sorted(by: { $0.0 < $1.0 }) {
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            if let data = try? Data(contentsOf: url) {
                hasher.update(data: data)
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
