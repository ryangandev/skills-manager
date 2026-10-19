# Skills Manager

A native macOS app for browsing, editing, syncing and importing skills for Claude Code and Codex.
It lists the skills you wrote or installed; agent built-ins stay hidden unless you ask for them.
Docs start at [docs/README.md](docs/README.md).

## Commands

- `swift test` runs the SkillsCore tests (Swift Testing).
- `Scripts/run.sh` builds a debug app bundle into `build/SkillsManager.app` and relaunches it.
- `Scripts/package_app.sh release` builds an ad-hoc signed release bundle.

There is no Xcode project; SwiftPM is the only build.

## Rules that fail silently

- Test file-changing flows against a sandbox, never your real `~/.claude` or `~/.codex`. Set `CLAUDE_CONFIG_DIR` and `CODEX_HOME` when you launch the app. See [Testing against a sandbox](docs/architecture.md#testing-against-a-sandbox).
- Never rewrite frontmatter you didn't change: keys the app doesn't know must survive a save byte for byte. See [SKILL.md parsing](docs/architecture.md#skillmd-parsing).
- Never delete a skill outright: move it to the Trash, or remove only the link when it is a symlink. Codex built-in skills (`~/.codex/skills/.system`) are read-only. See [Install and remove](docs/architecture.md#install-and-remove).
- In a SwiftUI `List(selection:)`, `.tag` must be the row's outermost modifier, or clicks silently select nothing. See [SwiftUI pitfalls](docs/architecture.md#swiftui-pitfalls).
- The app target defaults to `MainActor` isolation and SkillsCore does not, so core code that touches UI state must say so explicitly. See [Code map](docs/architecture.md#code-map).
