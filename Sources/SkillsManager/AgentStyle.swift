import SkillsCore
import SwiftUI

extension Agent {
    var tint: Color {
        switch self {
        case .claude: .adaptive(light: 0x8F3A18, dark: 0xF2B49A)
        case .codex: Color(nsColor: .systemGray)
        }
    }

    var homePathLabel: String {
        switch self {
        case .claude: "~/.claude/skills"
        case .codex: "~/.codex/skills"
        }
    }
}

extension SyncStatus {
    var title: String {
        switch self {
        case .linked: "Linked"
        case .identical: "In sync"
        case .differs: "Out of sync"
        case .only(let agent): "\(agent.displayName) only"
        case .builtin(let agent): "\(agent.displayName) built-in"
        }
    }

    /// Green for shared copies, orange for drift, gray otherwise.
    var tint: Color {
        switch self {
        case .linked, .identical: .okText
        case .differs: .warningText
        case .only, .builtin: .secondary
        }
    }
}

struct AgentBadge: View {
    let agent: Agent
    /// Increased inside a selected list row, where the tinted text would sit on the accent color.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let onSelection = prominence == .increased
        Text(agent.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(onSelection ? Color.white : agent == .codex ? Color.primary.opacity(0.75) : agent.tint)
            .background(onSelection ? Color.white.opacity(0.22) : agent.tint.opacity(agent == .codex ? 0.18 : 0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct StatusPill: View {
    let status: SyncStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.14), in: Capsule())
    }
}

struct AgentDot: View {
    let agent: Agent

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(agent.tint)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

extension Color {
    /// Readable green and orange for small text; the system colors are too light on white.
    static let okText = Color.adaptive(light: 0x1B6E34, dark: 0x7FD69A)
    static let warningText = Color.adaptive(light: 0x8A5300, dark: 0xF5B66E)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
