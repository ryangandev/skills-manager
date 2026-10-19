import Foundation

/// A skill found inside an import source, not yet installed.
public struct ImportCandidate: Sendable, Hashable, Identifiable {
    public var folderURL: URL
    /// Where it sat inside the source, for display.
    public var relativePath: String
    public var document: SkillDocument

    public var id: String { folderURL.path }
    public var folderName: String { folderURL.lastPathComponent }
    public var name: String { document.name ?? folderName }
    public var summary: String { document.description ?? "" }

    /// The folder name to install under: the declared name when it is valid, else the folder's own.
    public var installName: String {
        if let name = document.name, SkillValidator.nameIssues(name).isEmpty { return name }
        return folderName
    }
}

/// A GitHub repository, optionally narrowed to a branch and subfolder.
public struct GitHubSource: Sendable, Hashable {
    public var owner: String
    public var repo: String
    public var ref: String?
    public var subpath: String?

    /// Accepts `owner/repo`, `https://github.com/owner/repo`, and
    /// `https://github.com/owner/repo/tree/<ref>/<path>` (a ref without slashes).
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasPrefix("github.com/") { text.removeFirst("github.com/".count) }
        else if text.contains(".") && text.split(separator: "/").first?.contains(".") == true { return nil }

        var parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        owner = parts.removeFirst()
        repo = parts.removeFirst()
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        let allowed = { (value: String) in value.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }
        guard !owner.isEmpty, !repo.isEmpty, allowed(owner), allowed(repo) else { return nil }

        if parts.first == "tree" || parts.first == "blob", parts.count >= 2 {
            ref = parts[1]
            let rest = parts.dropFirst(2).filter { $0 != ".." && $0 != "." }
            subpath = rest.isEmpty ? nil : rest.joined(separator: "/")
            if parts.first == "blob", subpath?.hasSuffix("SKILL.md") == true {
                subpath = (subpath! as NSString).deletingLastPathComponent
                if subpath?.isEmpty == true { subpath = nil }
            }
        } else {
            ref = nil
            subpath = nil
        }
    }

    public var displayName: String {
        var name = "\(owner)/\(repo)"
        if let ref { name += " @ \(ref)" }
        if let subpath { name += " / \(subpath)" }
        return name
    }

    public var tarballURL: URL {
        var url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/tarball")!
        if let ref { url.appendPathComponent(ref) }
        return url
    }

    public var webURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)")!
    }
}

public enum SkillImportError: LocalizedError {
    case download(String)
    case extraction(String)
    case nothingFound

    public var errorDescription: String? {
        switch self {
        case .download(let message): "Download failed: \(message)"
        case .extraction(let message): "Could not unpack the archive: \(message)"
        case .nothingFound: "No SKILL.md files were found in that source."
        }
    }
}

public enum SkillImporter {
    /// Finds skill folders under `root`. A folder with a SKILL.md is a skill and is not searched further.
    public static func findSkills(in root: URL, maxDepth: Int = 6) -> [ImportCandidate] {
        let fm = FileManager.default
        let base = root.standardizedFileURL
        var results: [ImportCandidate] = []

        func visit(_ folder: URL, depth: Int) {
            let skillFile = folder.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: skillFile.path) {
                let text = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
                let path = folder.standardizedFileURL.path
                let relative = path == base.path ? folder.lastPathComponent : String(path.dropFirst(base.path.count + 1))
                results.append(ImportCandidate(folderURL: folder, relativePath: relative, document: .parse(text)))
                return
            }
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(
                      at: folder,
                      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                      options: [.skipsHiddenFiles]
                  )
            else { return }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if ["node_modules", ".git"].contains(child.lastPathComponent) { continue }
                visit(child, depth: depth + 1)
            }
        }

        visit(base, depth: 0)
        return results
    }

    /// A fresh, empty working folder for one import.
    public static func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsManager-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Unpacks a .zip (or .skill) archive into `destination`.
    public static func extractZip(_ archive: URL, to destination: URL) throws {
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
    }

    /// Downloads a repository snapshot and returns the folder to scan.
    public static func download(_ source: GitHubSource, into workspace: URL) async throws -> URL {
        var request = URLRequest(url: source.tarballURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsManager", forHTTPHeaderField: "User-Agent")
        let (file, response): (URL, URLResponse)
        do {
            (file, response) = try await URLSession.shared.download(for: request)
        } catch {
            throw SkillImportError.download(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = http.statusCode == 404 ? "repository or branch not found (private repositories are not supported yet)" : "HTTP \(http.statusCode)"
            throw SkillImportError.download(reason)
        }
        let archive = workspace.appendingPathComponent("source.tar.gz")
        try FileManager.default.moveItem(at: file, to: archive)
        let unpacked = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try run("/usr/bin/tar", ["-xzf", archive.path, "-C", unpacked.path])

        let top = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        guard top.count == 1, let repoRoot = top.first else {
            throw SkillImportError.extraction("unexpected archive layout")
        }
        guard let subpath = source.subpath else { return repoRoot }
        let target = repoRoot.appendingPathComponent(subpath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw SkillImportError.extraction("\(subpath) is not in the repository")
        }
        return target
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SkillImportError.extraction(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Remembers where imported skills came from.
public struct ImportSourceStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var standard: ImportSourceStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ImportSourceStore(fileURL: support.appendingPathComponent("SkillsManager/import-sources.json"))
    }

    public func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public func record(_ source: String, for names: [String]) throws {
        var all = load()
        for name in names { all[name] = source }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(all).write(to: fileURL, options: .atomic)
    }
}
