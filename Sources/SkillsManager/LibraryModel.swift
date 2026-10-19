import AppKit
import Observation
import SkillsCore

enum SidebarFilter: Hashable {
    case all
    case sync
    case agent(Agent)
    case shared
    case only(Agent)
    case differs

    var title: String {
        switch self {
        case .all: "All Skills"
        case .sync: "Agents & Sync"
        case .agent(let agent): agent.displayName
        case .shared: "In Both Agents"
        case .only(let agent): "\(agent.displayName) Only"
        case .differs: "Out of Sync"
        }
    }

    func includes(_ skill: Skill) -> Bool {
        switch self {
        case .all, .sync: true
        case .agent(let agent): skill.agents.contains(agent)
        case .shared: skill.status.isShared
        case .only(let agent): !skill.status.isShared && skill.agents == [agent]
        case .differs: skill.status == .differs
        }
    }
}

enum ActiveSheet: Identifiable {
    case newSkill(duplicating: Skill?)
    case importSkills
    case install(Skill, into: Agent)

    var id: String {
        switch self {
        case .newSkill(let skill): "new-\(skill?.id ?? "")"
        case .importSkills: "import"
        case .install(let skill, let agent): "install-\(skill.id)-\(agent.rawValue)"
        }
    }
}

/// The app's state: every skill on disk, what is selected, and the actions that change files.
@Observable
final class LibraryModel {
    let locations: AgentLocations
    let operations: SkillOperations
    let sourceStore: ImportSourceStore

    private(set) var skills: [Skill] = []
    private(set) var importSources: [String: String] = [:]
    private(set) var hasLoaded = false

    var filter: SidebarFilter = .all
    var selection: Skill.ID?
    var search = ""
    var sheet: ActiveSheet?
    /// While set, the editor takes the whole window in place of the library columns.
    var editor: EditorSession?
    var errorMessage: String?
    /// Agent built-ins (Codex's `.system` skills) are hidden by default, so the library shows only
    /// skills the user wrote or installed.
    var showsBuiltins = UserDefaults.standard.bool(forKey: LibraryModel.showsBuiltinsKey) {
        didSet {
            UserDefaults.standard.set(showsBuiltins, forKey: LibraryModel.showsBuiltinsKey)
            if !showsBuiltins, selectedSkill?.isBuiltin == true { selection = nil }
        }
    }

    private static let showsBuiltinsKey = "showsBuiltins"

    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(locations: AgentLocations = .current, sourceStore: ImportSourceStore = .standard) {
        self.locations = locations
        self.operations = SkillOperations(locations: locations)
        self.sourceStore = sourceStore
    }

    func start() {
        guard watcher == nil else { return }
        reload()
        watcher = DirectoryWatcher(paths: locations.watchedRoots) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        reloadTask?.cancel()
        let scanner = SkillScanner(locations: locations)
        reloadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { scanner.scan() }.value
            guard !Task.isCancelled else { return }
            skills = result
            importSources = sourceStore.load()
            hasLoaded = true
            if let selection, !result.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
            if let editor {
                if let fresh = result.first(where: { $0.id == editor.skill.id }) {
                    editor.update(skill: fresh)
                } else if !editor.isDirty {
                    self.editor = nil
                }
            }
        }
    }

    /// Waits for the reload in flight, so a caller can select something it just created.
    func reloadAndWait() async {
        reload()
        await reloadTask?.value
    }

    // MARK: Queries

    /// Every skill the library lists, before the sidebar filter and search.
    var listedSkills: [Skill] {
        showsBuiltins ? skills : skills.filter { !$0.isBuiltin }
    }

    var hiddenBuiltinCount: Int {
        showsBuiltins ? 0 : skills.count(where: \.isBuiltin)
    }

    var visibleSkills: [Skill] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return listedSkills.filter { skill in
            guard filter.includes(skill) else { return false }
            guard !query.isEmpty else { return true }
            return skill.name.localizedCaseInsensitiveContains(query)
                || skill.summary.localizedCaseInsensitiveContains(query)
                || skill.files.contains { $0.relativePath.localizedCaseInsensitiveContains(query) }
        }
    }

    func count(_ filter: SidebarFilter) -> Int {
        listedSkills.filter(filter.includes).count
    }

    var selectedSkill: Skill? {
        guard let selection else { return nil }
        return skills.first { $0.id == selection }
    }

    func skill(id: Skill.ID) -> Skill? {
        skills.first { $0.id == id }
    }

    // MARK: Actions

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func remove(_ install: SkillInstall) {
        perform { try operations.remove(install) }
    }

    /// Picking another skill closes the editor, unless it has unsaved changes:
    /// then the editor asks first and applies the pick if the user discards.
    func requestSelection(_ id: Skill.ID?) {
        guard id != selection else { return }
        if let editor {
            guard !editor.isDirty else {
                editor.pendingSelection = .some(id)
                return
            }
            self.editor = nil
        }
        selection = id
    }

    func beginEditing(_ skill: Skill) {
        guard !skill.isBuiltin else { return }
        selection = skill.id
        editor = EditorSession(skill: skill, operations: operations)
    }

    /// Opens the editor on a skill that was just written, once the rescan has picked it up.
    func select(andEdit id: Skill.ID) async {
        await reloadAndWait()
        if filter != .all, let skill = skill(id: id), !filter.includes(skill) {
            filter = .all
        }
        selection = id
        if let skill = skill(id: id) {
            beginEditing(skill)
        }
    }
}
