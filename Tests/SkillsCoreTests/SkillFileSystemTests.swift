import Foundation
import Testing
@testable import SkillsCore

/// A throwaway home folder with Claude Code and Codex skills folders.
struct Sandbox {
    let home: URL
    let locations: AgentLocations

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsCoreTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        locations = AgentLocations(home: home)
        for agent in Agent.allCases {
            try FileManager.default.createDirectory(at: locations.skillsRoot(for: agent), withIntermediateDirectories: true)
        }
    }

    @discardableResult
    func makeSkill(_ name: String, in root: URL, description: String = "Does a thing.", extraFiles: [String: String] = [:]) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(description)\n---\n\n# \(name)\n"
            .write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for (path, text) in extraFiles {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return folder
    }

    func root(_ agent: Agent) -> URL { locations.skillsRoot(for: agent) }

    func cleanup() { try? FileManager.default.removeItem(at: home) }
}

@Suite struct SkillScannerTests {
    @Test func groupsCopiesAcrossAgentsAndDetectsStatus() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        try box.makeSkill("shared", in: box.root(.claude))
        try box.makeSkill("shared", in: box.root(.codex))
        try box.makeSkill("drifted", in: box.root(.claude))
        try box.makeSkill("drifted", in: box.root(.codex), description: "Changed.")
        let linkedSource = try box.makeSkill("linked", in: box.root(.claude))
        try FileManager.default.createSymbolicLink(at: box.root(.codex).appendingPathComponent("linked"), withDestinationURL: linkedSource)
        try box.makeSkill("solo", in: box.root(.claude), extraFiles: ["scripts/run.sh": "echo hi"])
        try box.makeSkill("imagegen", in: box.root(.codex).appendingPathComponent(".system"))
        try FileManager.default.createDirectory(at: box.root(.claude).appendingPathComponent("not-a-skill"), withIntermediateDirectories: true)

        let skills = SkillScanner(locations: box.locations).scan()
        let byID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })

        #expect(Set(byID.keys) == ["shared", "drifted", "linked", "solo", "codex-builtin/imagegen"])
        #expect(byID["shared"]?.status == .identical)
        #expect(byID["drifted"]?.status == .differs)
        #expect(byID["linked"]?.status == .linked)
        #expect(byID["linked"]?.install(for: .codex)?.isSymlink == true)
        #expect(byID["linked"]?.primaryInstall.agent == .claude)
        #expect(byID["solo"]?.status == .only(.claude))
        #expect(byID["solo"]?.files.map(\.relativePath) == ["SKILL.md", "scripts", "scripts/run.sh"])
        #expect(byID["codex-builtin/imagegen"]?.status == .builtin(.codex))
        #expect(skills.map(\.name) == ["drifted", "imagegen", "linked", "shared", "solo"])
    }

    @Test func toleratesMissingFolders() {
        let locations = AgentLocations(home: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(SkillScanner(locations: locations).scan().isEmpty)
    }
}

@Suite struct SkillOperationsTests {
    @Test func installsBySymlinkAndCopy() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let source = try box.makeSkill("tool", in: box.root(.claude))
        let ops = SkillOperations(locations: box.locations)

        let link = try ops.install(folder: source, named: "tool", into: .codex, method: .symlink)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == source.path)
        #expect(throws: SkillOperationError.destinationExists(link)) {
            try ops.install(folder: source, named: "tool", into: .codex, method: .copy)
        }

        try FileManager.default.removeItem(at: link)
        let copy = try ops.install(folder: source, named: "tool", into: .codex, method: .copy)
        #expect((try? copy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false)
        #expect(SkillScanner(locations: box.locations).scan().first?.status == .identical)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: box.root(.codex).path)
        #expect(leftovers == ["tool"])
    }

    @Test func savingWritesEachDistinctFolderOnce() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let source = try box.makeSkill("tool", in: box.root(.claude))
        let ops = SkillOperations(locations: box.locations)
        try ops.install(folder: source, named: "tool", into: .codex, method: .copy)

        let skill = try #require(SkillScanner(locations: box.locations).scan().first)
        var doc = skill.document
        doc.setValue("Updated.", for: "description")
        try ops.write(doc.serialized(), relativePath: "SKILL.md", to: skill.installs.map(\.resolvedURL))

        let after = try #require(SkillScanner(locations: box.locations).scan().first)
        #expect(after.status == .identical)
        #expect(after.summary == "Updated.")
    }

    @Test func createsSkillsFromTemplates() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let ops = SkillOperations(locations: box.locations)

        try ops.create(name: "release-notes", description: "Draft notes.", template: .withResources, agents: [.codex, .claude], method: .symlink)
        let created = try #require(SkillScanner(locations: box.locations).scan().first { $0.id == "release-notes" })
        #expect(created.status == .linked)
        #expect(created.primaryInstall.agent == .claude)
        #expect(created.files.contains { $0.relativePath == "scripts" && $0.isDirectory })

        let builtin = try box.makeSkill("imagegen", in: box.root(.codex).appendingPathComponent(".system"), extraFiles: ["assets/a.txt": "x"])
        try ops.create(name: "imagegen-copy", description: "Mine.", template: .duplicate(of: builtin), agents: [.codex], method: .copy)
        let copy = try #require(SkillScanner(locations: box.locations).scan().first { $0.id == "imagegen-copy" })
        #expect(copy.name == "imagegen-copy")
        #expect(copy.summary == "Mine.")
        #expect(copy.files.contains { $0.relativePath == "assets/a.txt" })

        #expect(throws: SkillOperationError.invalidName("Bad Name")) {
            try ops.create(name: "Bad Name", description: "x", template: .blank, agents: [.claude], method: .copy)
        }
    }

    @Test func removingALinkLeavesTheSourceAlone() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let source = try box.makeSkill("tool", in: box.root(.claude))
        let ops = SkillOperations(locations: box.locations)
        try ops.install(folder: source, named: "tool", into: .codex, method: .symlink)
        let skill = try #require(SkillScanner(locations: box.locations).scan().first)

        try ops.remove(try #require(skill.install(for: .codex)))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
        #expect(SkillScanner(locations: box.locations).scan().first?.status == .only(.claude))
    }

    @Test func refusesToChangeBuiltins() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        try box.makeSkill("imagegen", in: box.root(.codex).appendingPathComponent(".system"))
        let skill = try #require(SkillScanner(locations: box.locations).scan().first)
        #expect(throws: SkillOperationError.readOnly("imagegen")) {
            try SkillOperations(locations: box.locations).remove(skill.installs[0])
        }
    }
}

@Suite struct SkillImporterTests {
    @Test func findsNestedSkillsWithoutDescendingIntoThem() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let repo = box.home.appendingPathComponent("repo", isDirectory: true)
        try box.makeSkill("pdf", in: repo.appendingPathComponent("skills"), extraFiles: ["inner/SKILL.md": "---\nname: inner\n---\n"])
        try box.makeSkill("docx", in: repo.appendingPathComponent("skills"))
        try box.makeSkill("hidden", in: repo.appendingPathComponent(".git"))

        let found = SkillImporter.findSkills(in: repo)
        #expect(found.map(\.relativePath) == ["skills/docx", "skills/pdf"])
        #expect(found.map(\.installName) == ["docx", "pdf"])

        let single = SkillImporter.findSkills(in: repo.appendingPathComponent("skills/pdf"))
        #expect(single.map(\.relativePath) == ["pdf"])
    }

    @Test func importsIntoSeveralAgentsAndRejectsEscapingLinks() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let incoming = box.home.appendingPathComponent("incoming", isDirectory: true)
        let source = try box.makeSkill("pdf", in: incoming)
        let ops = SkillOperations(locations: box.locations)

        let created = try ops.importFolder(source, named: "pdf", into: [.claude, .codex], method: .symlink)
        #expect(created.count == 2)
        #expect(SkillScanner(locations: box.locations).scan().first?.status == .linked)

        let sneaky = try box.makeSkill("sneaky", in: incoming)
        try FileManager.default.createSymbolicLink(at: sneaky.appendingPathComponent("secrets"), withDestinationURL: box.home)
        #expect(throws: SkillOperationError.self) {
            try ops.importFolder(sneaky, named: "sneaky", into: [.claude], method: .copy)
        }
        #expect(!ops.exists("sneaky", in: .claude))
    }

    @Test func extractsZipArchives() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let source = try box.makeSkill("zipped", in: box.home.appendingPathComponent("src"))
        let archive = box.home.appendingPathComponent("zipped.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", source.path, archive.path]
        try zip.run()
        zip.waitUntilExit()

        let workspace = try SkillImporter.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try SkillImporter.extractZip(archive, to: workspace)
        #expect(SkillImporter.findSkills(in: workspace).map(\.name) == ["zipped"])
    }

    @Test func remembersImportSources() throws {
        let box = try Sandbox()
        defer { box.cleanup() }
        let store = ImportSourceStore(fileURL: box.home.appendingPathComponent("support/sources.json"))
        try store.record("anthropics/skills", for: ["pdf", "docx"])
        try store.record("me/other", for: ["pdf"])
        #expect(store.load() == ["pdf": "me/other", "docx": "anthropics/skills"])
    }
}
