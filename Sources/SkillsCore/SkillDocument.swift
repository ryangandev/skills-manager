import Foundation

/// A parsed `SKILL.md`: YAML frontmatter plus the Markdown body.
///
/// Parsing keeps every frontmatter line as written, so saving a document
/// only rewrites the keys that were changed and leaves the rest untouched.
public struct SkillDocument: Sendable, Hashable {
    /// One top-level frontmatter key with all of its lines, or a run of
    /// comment and blank lines (`key == nil`).
    public struct Entry: Sendable, Hashable {
        public var key: String?
        public var lines: [String]
    }

    public var hasFrontmatter: Bool
    public var entries: [Entry]
    public var body: String

    public init(hasFrontmatter: Bool = true, entries: [Entry] = [], body: String = "") {
        self.hasFrontmatter = hasFrontmatter
        self.entries = entries
        self.body = body
    }

    public var name: String? { value(for: "name") }
    public var description: String? { value(for: "description") }

    /// Keys other than `name` and `description`, in file order.
    public var otherKeys: [String] {
        entries.compactMap(\.key).filter { $0 != "name" && $0 != "description" }
    }

    // MARK: Parsing

    public static func parse(_ text: String) -> SkillDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.indices.dropFirst().first(where: {
                  lines[$0].trimmingCharacters(in: .whitespaces) == "---"
              })
        else {
            return SkillDocument(hasFrontmatter: false, entries: [], body: normalized)
        }

        var entries: [Entry] = []
        for line in lines[1..<close] {
            if let key = topLevelKey(in: line) {
                entries.append(Entry(key: key, lines: [line]))
            } else if let last = entries.indices.last, entries[last].key != nil, isContinuation(line) {
                entries[last].lines.append(line)
            } else if let last = entries.indices.last, entries[last].key == nil {
                entries[last].lines.append(line)
            } else {
                entries.append(Entry(key: nil, lines: [line]))
            }
        }
        let body = lines[(close + 1)...].joined(separator: "\n")
        return SkillDocument(hasFrontmatter: true, entries: entries, body: body)
    }

    private static func topLevelKey(in line: String) -> String? {
        guard let first = line.first, !first.isWhitespace, first != "#", first != "-" else { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon]
        let rest = line[line.index(after: colon)...]
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        return String(key)
    }

    private static func isContinuation(_ line: String) -> Bool {
        line.isEmpty || line.first?.isWhitespace == true || line.hasPrefix("- ")
    }

    // MARK: Values

    /// The decoded scalar value of a top-level key.
    public func value(for key: String) -> String? {
        guard let entry = entries.first(where: { $0.key == key }) else { return nil }
        return Self.decodeScalar(entry.lines, key: key)
    }

    static func decodeScalar(_ lines: [String], key: String) -> String? {
        guard let first = lines.first else { return nil }
        let head = first.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        let rest = Array(lines.dropFirst())

        if let indicator = head.first, indicator == "|" || indicator == ">" {
            let content = dedent(rest)
            let trimmedTrailing = trimTrailingBlankLines(content)
            if indicator == "|" {
                return trimmedTrailing.joined(separator: "\n")
            }
            return fold(trimmedTrailing)
        }

        if head.hasPrefix("\"") {
            let joined = ([head] + rest.map { $0.trimmingCharacters(in: .whitespaces) }).joined(separator: " ")
            return unescapeDoubleQuoted(joined)
        }
        if head.hasPrefix("'") {
            let joined = ([head] + rest.map { $0.trimmingCharacters(in: .whitespaces) }).joined(separator: " ")
            var inner = Substring(joined.dropFirst())
            if inner.hasSuffix("'") { inner = inner.dropLast() }
            return inner.replacingOccurrences(of: "''", with: "'")
        }

        let continuation = rest.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let plain = ([head] + continuation).filter { !$0.isEmpty }.joined(separator: " ")
        return stripComment(plain)
    }

    private static func dedent(_ lines: [String]) -> [String] {
        let indent = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
            .min() ?? 0
        return lines.map { $0.count >= indent ? String($0.dropFirst(indent)) : "" }
    }

    private static func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        var result = lines
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result
    }

    private static func fold(_ lines: [String]) -> String {
        var output = ""
        var pendingBreak = false
        for line in lines {
            if line.isEmpty {
                output += "\n"
                pendingBreak = false
                continue
            }
            if pendingBreak { output += " " }
            output += line
            pendingBreak = true
        }
        return output
    }

    private static func unescapeDoubleQuoted(_ raw: String) -> String {
        var chars = Substring(raw.dropFirst())
        if chars.hasSuffix("\"") { chars = chars.dropLast() }
        var result = ""
        var iterator = chars.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\" else {
                result.append(ch)
                continue
            }
            switch iterator.next() {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case let other?: result.append("\\"); result.append(other)
            case nil: result.append("\\")
            }
        }
        return result
    }

    private static func stripComment(_ value: String) -> String {
        guard let range = value.range(of: " #") else { return value }
        return String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Editing

    /// Sets a top-level scalar, replacing the key in place or appending it.
    public mutating func setValue(_ value: String, for key: String) {
        let lines = Self.encodeScalar(value, key: key)
        hasFrontmatter = true
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].lines = lines
        } else {
            entries.append(Entry(key: key, lines: lines))
        }
    }

    static func encodeScalar(_ value: String, key: String) -> [String] {
        if value.contains("\n") {
            let body = value.components(separatedBy: "\n").map { $0.isEmpty ? "" : "  " + $0 }
            return ["\(key): |-"] + body
        }
        if isSafePlainScalar(value) {
            return ["\(key): \(value)"]
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\t", with: "\\t")
        return ["\(key): \"\(escaped)\""]
    }

    private static func isSafePlainScalar(_ value: String) -> Bool {
        guard let first = value.first, let last = value.last else { return false }
        if first.isWhitespace || last.isWhitespace { return false }
        if "-?:,[]{}#&*!|>'\"%@`".contains(first) { return false }
        if value.contains(": ") || value.contains(" #") || value.contains("\t") || value.hasSuffix(":") { return false }
        let reserved = ["true", "false", "yes", "no", "null", "on", "off", "~"]
        if reserved.contains(value.lowercased()) || Double(value) != nil { return false }
        return true
    }

    // MARK: Serializing

    public func serialized() -> String {
        guard hasFrontmatter else { return body }
        let frontmatter = entries.flatMap(\.lines)
        return (["---"] + frontmatter + ["---"]).joined(separator: "\n") + "\n" + body
    }

    /// A new skill's starting `SKILL.md`.
    public static func template(name: String, description: String, title: String? = nil) -> SkillDocument {
        var document = SkillDocument(hasFrontmatter: true, entries: [], body: "")
        document.setValue(name, for: "name")
        document.setValue(description, for: "description")
        let heading = title ?? name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        document.body = "\n# \(heading)\n\n"
        return document
    }
}
