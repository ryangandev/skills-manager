import SkillsCore
import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            if let editor = model.editor {
                SkillEditorView(session: editor)
                    .id(editor.id)
            } else {
                library
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .newSkill(let source):
                NewSkillSheet(duplicating: source)
            case .importSkills:
                ImportSheet()
            case .install(let skill, let agent):
                InstallSheet(skill: skill, agent: agent)
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var library: some View {
        @Bindable var model = model

        return splitView
            .navigationTitle(model.filter.title)
            .navigationSubtitle(countLabel)
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search name, description, files")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.sheet = .importSkills
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import skills from GitHub, a folder or a ZIP file")
                    Button {
                        model.sheet = .newSkill(duplicating: nil)
                    } label: {
                        Label("New Skill", systemImage: "plus")
                    }
                    .help("Create a new skill")
                }
            }
    }

    /// The sync table compares every skill across agents, so it gets the full width instead of a detail column.
    @ViewBuilder
    private var splitView: some View {
        if model.filter == .sync {
            NavigationSplitView {
                sidebar
            } detail: {
                SyncTableView()
            }
        } else {
            NavigationSplitView {
                sidebar
            } content: {
                SkillListView()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
            } detail: {
                DetailColumn()
            }
        }
    }

    private var sidebar: some View {
        SidebarView()
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    }

    private var countLabel: String {
        let count = model.visibleSkills.count
        return count == 1 ? "1 skill" : "\(count) skills"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct DetailColumn: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if let skill = model.selectedSkill {
            SkillDetailView(skill: skill)
        } else if model.hasLoaded && model.listedSkills.isEmpty {
            ContentUnavailableView {
                Label("No Skills Yet", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Nothing in ~/.claude/skills or ~/.codex/skills. Create a skill or import one to get started.")
            } actions: {
                Button("New Skill…") { model.sheet = .newSkill(duplicating: nil) }
                Button("Import…") { model.sheet = .importSkills }
            }
        } else {
            ContentUnavailableView("Select a Skill", systemImage: "doc.text", description: Text("Pick a skill to see where it is installed and what it contains."))
        }
    }
}
