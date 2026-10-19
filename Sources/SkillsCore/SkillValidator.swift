import Foundation

public struct SkillIssue: Sendable, Hashable, Identifiable {
    public enum Severity: Sendable, Hashable {
        case error
        case warning
    }

    public var severity: Severity
    public var title: String
    public var detail: String

    public var id: String { title + detail }

    public init(_ severity: Severity, _ title: String, _ detail: String = "") {
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// Checks a skill against the rules both agents share: a kebab-case name of at
/// most 64 characters that matches its folder, and a description of at most
/// 1024 characters.
public enum SkillValidator {
    public static let maxNameLength = 64
    public static let maxDescriptionLength = 1024

    public static func nameIssues(_ name: String) -> [SkillIssue] {
        if name.isEmpty {
            return [SkillIssue(.error, "Name is required")]
        }
        var issues: [SkillIssue] = []
        if name.count > maxNameLength {
            issues.append(SkillIssue(.error, "Name is too long", "\(name.count) of \(maxNameLength) characters"))
        }
        let allowed = name.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        if !allowed {
            issues.append(SkillIssue(.error, "Use lowercase letters, numbers and hyphens"))
        } else if name.hasPrefix("-") || name.hasSuffix("-") || name.contains("--") {
            issues.append(SkillIssue(.error, "Hyphens can only sit between words"))
        }
        return issues
    }

    public static func descriptionIssues(_ description: String) -> [SkillIssue] {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [SkillIssue(.error, "Description is required", "Agents read it to decide when to load the skill.")]
        }
        if description.count > maxDescriptionLength {
            return [SkillIssue(.error, "Description is too long", "\(description.count) of \(maxDescriptionLength) characters")]
        }
        return []
    }

    public static func issues(for document: SkillDocument, folderName: String) -> [SkillIssue] {
        guard document.hasFrontmatter else {
            return [SkillIssue(.error, "Missing frontmatter", "SKILL.md must start with a --- block holding name and description.")]
        }
        var issues: [SkillIssue] = []
        if let name = document.name {
            issues += nameIssues(name)
            if name != folderName {
                issues.append(SkillIssue(.warning, "Name does not match folder", "name is \(name), folder is \(folderName)"))
            }
        } else {
            issues.append(SkillIssue(.error, "Name is required"))
        }
        issues += descriptionIssues(document.description ?? "")
        return issues
    }
}
