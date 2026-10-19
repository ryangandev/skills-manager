import SwiftUI

@main
struct SkillsManagerApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        Window("Skills Manager", id: "library") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    applyDebugAppearance()
                    model.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.reload()
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Skill…") { model.sheet = .newSkill(duplicating: nil) }
                    .keyboardShortcut("n")
                Button("Import Skills…") { model.sheet = .importSkills }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Toggle("Show Built-in Skills", isOn: $model.showsBuiltins)
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                Button("Reload Skills") { model.reload() }
                    .keyboardShortcut("r")
            }
        }
    }

    /// Debug builds can force light or dark with SKILLS_MANAGER_APPEARANCE, to check both without touching system settings.
    private func applyDebugAppearance() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["SKILLS_MANAGER_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
    }
}
