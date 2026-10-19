import SkillsCore
import SwiftUI

/// A selectable card used for radio-style choices in sheets.
struct ChoiceCard: View {
    let title: String
    let detail: String
    var badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).fontWeight(.semibold)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            // Fill the row's height so cards side by side line up when their text wraps differently.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CheckRow: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark" : "xmark")
                .foregroundStyle(ok ? Color.okText : Color.red)
                .fontWeight(.bold)
        }
        .font(.callout)
    }
}

struct MethodPicker: View {
    @Binding var method: InstallMethod
    let primaryAgent: Agent
    var allowsLink = true

    var body: some View {
        VStack(spacing: 8) {
            if allowsLink {
                ChoiceCard(
                    title: "Link to the \(primaryAgent.displayName) copy",
                    detail: "Creates a symlink. One source of truth, so an edit shows up in both agents.",
                    badge: "Recommended",
                    isSelected: method == .symlink
                ) { method = .symlink }
            }
            ChoiceCard(
                title: "Make a separate copy",
                detail: "Copies the folder. Each agent's version can then change on its own.",
                isSelected: method == .copy || !allowsLink
            ) { method = .copy }
        }
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.callout.weight(.semibold))
    }
}
