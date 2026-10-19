import SkillsCore
import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                row(.all, icon: "square.stack.3d.up")
                row(.sync, icon: "arrow.left.arrow.right")
            }
            Section("Agents") {
                ForEach(Agent.allCases) { agent in
                    HStack(spacing: 8) {
                        AgentDot(agent: agent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.displayName)
                            Text(model.locations.skillsRoot(for: agent).abbreviatedPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .badge(model.count(.agent(agent)))
                    .tag(SidebarFilter.agent(agent))
                }
            }
            Section("Status") {
                row(.shared, icon: "link")
                ForEach(Agent.allCases) { agent in
                    row(.only(agent), icon: "circle.lefthalf.filled")
                }
                if model.count(.differs) > 0 {
                    row(.differs, icon: "exclamationmark.triangle")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if model.hiddenBuiltinCount > 0 {
                BuiltinFooter(count: model.hiddenBuiltinCount) { model.showsBuiltins = true }
            }
        }
    }

    /// List selection on macOS expects an optional; nil (clicking empty space) keeps the current filter.
    private var selection: Binding<SidebarFilter?> {
        Binding(
            get: { model.filter },
            set: { if let filter = $0 { model.filter = filter } }
        )
    }

    private func row(_ filter: SidebarFilter, icon: String) -> some View {
        Label(filter.title, systemImage: icon)
            .badge(filter == .sync ? 0 : model.count(filter))
            .tag(filter)
    }
}

/// Says how many agent built-ins are hidden, with a way to show them.
private struct BuiltinFooter: View {
    let count: Int
    let show: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(count == 1 ? "1 built-in skill hidden" : "\(count) built-in skills hidden")
                .foregroundStyle(.secondary)
            Button("Show", action: show)
                .buttonStyle(.link)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
