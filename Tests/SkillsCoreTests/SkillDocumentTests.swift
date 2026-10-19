import Testing
@testable import SkillsCore

@Suite struct SkillDocumentTests {
    @Test func parsesPlainFrontmatter() {
        let doc = SkillDocument.parse("---\nname: agent-wiki\ndescription: Capture decisions; recall context.\n---\n\n# Agent Wiki\n")
        #expect(doc.hasFrontmatter)
        #expect(doc.name == "agent-wiki")
        #expect(doc.description == "Capture decisions; recall context.")
        #expect(doc.body == "\n# Agent Wiki\n")
    }

    @Test func parsesQuotedValues() {
        let doc = SkillDocument.parse("---\nname: \"imagegen\"\ndescription: \"Say \\\"hi\\\": now\"\nother: 'it''s'\n---\nbody")
        #expect(doc.name == "imagegen")
        #expect(doc.description == "Say \"hi\": now")
        #expect(doc.value(for: "other") == "it's")
    }

    @Test func parsesBlockScalars() {
        let folded = SkillDocument.parse("---\nname: x\ndescription: >\n  First line\n  second line.\n\n  New paragraph.\n---\n")
        #expect(folded.description == "First line second line.\nNew paragraph.")
        let literal = SkillDocument.parse("---\nname: x\ndescription: |\n  one\n  two\n---\n")
        #expect(literal.description == "one\ntwo")
    }

    @Test func roundTripsUntouchedDocument() {
        let text = "---\nname: x\n# a comment\nmetadata:\n  tags: [a, b]\ndescription: hello\n---\n\nBody text\n"
        #expect(SkillDocument.parse(text).serialized() == text)
    }

    @Test func editingKeepsOtherKeysInPlace() {
        var doc = SkillDocument.parse("---\nname: x\nlicense: MIT\ndescription: old\nallowed-tools:\n  - Read\n---\nBody")
        doc.setValue("New: value with colon", for: "description")
        #expect(doc.serialized() == "---\nname: x\nlicense: MIT\ndescription: \"New: value with colon\"\nallowed-tools:\n  - Read\n---\nBody")
        #expect(SkillDocument.parse(doc.serialized()).description == "New: value with colon")
        #expect(doc.otherKeys == ["license", "allowed-tools"])
    }

    @Test func encodesValuesThatNeedQuoting() {
        for value in ["true", "123", "#hash", "- dash", "trailing:", "say \"hi\""] {
            var doc = SkillDocument.parse("---\nname: x\n---\n")
            doc.setValue(value, for: "description")
            #expect(SkillDocument.parse(doc.serialized()).description == value, "round trip of \(value)")
        }
    }

    @Test func treatsMissingFrontmatterAsBody() {
        let doc = SkillDocument.parse("# Just markdown\n")
        #expect(!doc.hasFrontmatter)
        #expect(doc.name == nil)
        #expect(doc.serialized() == "# Just markdown\n")
    }

    @Test func templateIsValid() {
        let doc = SkillDocument.template(name: "release-notes", description: "Draft release notes.")
        #expect(doc.serialized().hasPrefix("---\nname: release-notes\ndescription: Draft release notes.\n---\n\n# Release Notes"))
        #expect(SkillValidator.issues(for: doc, folderName: "release-notes").isEmpty)
    }
}

@Suite struct SkillValidatorTests {
    @Test func acceptsKebabCaseNames() {
        #expect(SkillValidator.nameIssues("design-taste-frontend").isEmpty)
        #expect(SkillValidator.nameIssues("pdf2").isEmpty)
    }

    @Test func rejectsBadNames() {
        for name in ["", "Agent", "has space", "-lead", "trail-", "dou--ble", String(repeating: "a", count: 65)] {
            #expect(!SkillValidator.nameIssues(name).isEmpty, "\(name) should be rejected")
        }
    }

    @Test func flagsDescriptionAndFolderProblems() {
        let doc = SkillDocument.parse("---\nname: other\ndescription: \"\"\n---\n")
        let titles = SkillValidator.issues(for: doc, folderName: "folder").map(\.title)
        #expect(titles.contains("Name does not match folder"))
        #expect(titles.contains("Description is required"))
        let long = SkillValidator.descriptionIssues(String(repeating: "a", count: 1025))
        #expect(long.first?.title == "Description is too long")
    }
}

@Suite struct GitHubSourceTests {
    @Test func parsesCommonForms() {
        let short = GitHubSource("anthropics/skills")
        #expect(short?.owner == "anthropics" && short?.repo == "skills" && short?.ref == nil)

        let tree = GitHubSource("https://github.com/anthropics/skills/tree/main/skills/pdf")
        #expect(tree?.ref == "main")
        #expect(tree?.subpath == "skills/pdf")
        #expect(tree?.tarballURL.absoluteString == "https://api.github.com/repos/anthropics/skills/tarball/main")

        let blob = GitHubSource("github.com/o/r/blob/dev/a/SKILL.md")
        #expect(blob?.subpath == "a")

        #expect(GitHubSource("https://github.com/o/r.git")?.repo == "r")
    }

    @Test func rejectsOtherInput() {
        #expect(GitHubSource("gitlab.com/o/r") == nil)
        #expect(GitHubSource("just-one") == nil)
        #expect(GitHubSource("o/r/tree/main/../../etc")?.subpath == "etc")
    }
}
