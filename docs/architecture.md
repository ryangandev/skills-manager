# Architecture

Each section says how a subsystem works, why it works that way, and what to watch out for.

## Code map

The repo is a SwiftPM package for macOS 15+, built with swift-tools 6.2.

- `Sources/SkillsCore`: a library with no UI that does all the disk work and can be tested without the app.
  - `Agent.swift`: the `Agent` enum (Claude Code, Codex) and `AgentLocations`, which resolves each agent's skills folder.
  - `SkillDocument.swift`: the SKILL.md frontmatter parser and writer.
  - `SkillValidator.swift`: name and description rules.
  - `Skill.swift`: the `Skill`, `SkillInstall`, `SkillFile` and `SyncStatus` models.
  - `SkillScanner.swift`: finds skills on disk and groups them across agents.
  - `SkillOperations.swift`: every change the app makes on disk (create, install, write, remove).
  - `SkillImporter.swift`: GitHub, folder and ZIP import, plus `ImportSourceStore`.
  - `DirectoryWatcher.swift`: the FSEvents wrapper.
- `Sources/SkillsManager`: the SwiftUI app.
  This target sets `.defaultIsolation(MainActor.self)`, so its types are main-actor by default; SkillsCore is not, apart from `DirectoryWatcher`.
  - `LibraryModel.swift`: the single `@Observable` app state (skills, filter, selection, sheets, editor).
  - `EditorSession.swift`: unsaved edits for one skill.
  - The other files are the views, one per screen or sheet.
- `Tests/SkillsCoreTests`: Swift Testing suites that run against a temporary home folder (the `Sandbox` helper).
- `Scripts/package_app.sh`: wraps the built binary into `build/SkillsManager.app` with an Info.plist (bundle id `dev.ryangan.skillsmanager`), the app icon and an ad-hoc signature.
- `Resources/AppIcon.svg`: the app icon source; `Scripts/make_icon.sh` renders it into the committed `Resources/AppIcon.icns`, so rerun it after editing the SVG.
- `docs/images/screenshot.png`: the README screenshot, taken against a sandbox of sample skills so no personal skills show; retake it the same way when the UI changes.
  There is no Xcode project, so the package stays the single source of truth.

## Scanning and sync status

Claude Code skills live in `~/.claude/skills/<name>/SKILL.md`, or under `$CLAUDE_CONFIG_DIR` when that is set.
Codex skills live in `~/.codex/skills`, or under `$CODEX_HOME`.
Codex ships built-in skills in `~/.codex/skills/.system`.
The library hides them by default so it lists only skills the user wrote or installed; View > Show Built-in Skills (⇧⌘B) or the sidebar footer brings them back, and the choice is saved in `UserDefaults` (`showsBuiltins`).
When shown, they are read-only, with ids of the form `codex-builtin/<name>` so they never merge with a personal skill of the same name.

The scanner groups installs by folder name into one `Skill`.
A skill's `SyncStatus` is one of these:

- linked: one agent's folder is a symlink to the other's.
- identical: both are real folders with the same SHA-256 content hash.
- differs: both are real folders with different content.
- only(agent): only one agent has it.
- builtin(agent): a Codex built-in.

`primaryInstall` prefers a real folder over a link, so edits and copies always start from the real files.

## SKILL.md parsing

`SkillDocument` keeps the frontmatter as an ordered list of entries, each holding its raw lines.
Reading a value handles plain, single-quoted and double-quoted scalars and `|` and `>` block scalars.
Writing replaces only the entry being changed, and quotes the value only when a plain scalar would be unsafe.
This means keys the app doesn't understand (for example `license`, `allowed-tools` or `metadata`) survive a save exactly as written.
Don't swap this for a YAML library that round-trips through a dictionary: it would reorder keys and reformat values in other people's skills.

Validation follows the agents' rules: the name must be kebab-case, at most 64 characters, and match the folder name; the description is required and at most 1024 characters.
Renaming isn't supported yet, because the name must match the folder; the editor shows the name as read-only.

## Install and remove

Putting a skill into a second agent either symlinks it (the default, so one edit shows up in both agents) or copies it.
`InstallSheet` would only copy a built-in skill, never link it, because Codex may replace its built-ins at any time; the UI doesn't offer installing built-ins elsewhere today.
Copies and new skills are built in a hidden `.<name>.staging-<uuid>` folder next to the destination and moved into place, so a failed write never leaves a half-written skill an agent might load.
When both agents have real folders, saving in the editor writes each distinct resolved folder once, and only overwrites the other agent's copy if the user asks to.
Removing moves a real folder to the Trash, or deletes just the link if it is a symlink.
Nothing is ever deleted outright, and built-ins can't be removed.

## Import

Sources are a GitHub URL (`owner/repo`, a repository URL, a `/tree/<ref>/<path>` link or a `/blob/.../SKILL.md` link), a local folder, or a ZIP file.
GitHub sources are downloaded as a tarball from `api.github.com/repos/<owner>/<repo>/tarball/<ref>` and extracted with `/usr/bin/tar`; ZIP files are extracted with `/usr/bin/ditto -x -k`.
Everything is unpacked into a temporary workspace that is removed when the sheet closes.
The importer looks for SKILL.md files up to 6 folders deep and rejects any skill that contains a symlink pointing outside its own folder, so an import can't plant a link into the rest of the home folder.
The first chosen agent gets a real copy, and the others get a link or a copy, as chosen.

`ImportSourceStore` remembers where each skill came from in `~/Library/Application Support/SkillsManager/import-sources.json`, keyed by folder name.
It does not check sources for updates yet (see [status.md](status.md)).

## File watching

`DirectoryWatcher` watches only the agents' skills folders that exist, with FSEvents at 0.4 s latency.
It deliberately does not watch `~/.claude` or `~/.codex` themselves, because those change constantly (sessions, history) and would trigger endless rescans.
To catch a skills folder that is created later, the app also rescans whenever it becomes active.
The FSEvents callback gets a C pointer to the watcher; it passes it through `UInt(bitPattern:)` and hops onto the main actor with `MainActor.assumeIsolated` so Swift 6 strict concurrency accepts it.

## UI structure

The look follows the Claude Design artboards linked from [docs/README.md](README.md#ownership-and-updates): native macOS, with Claude Code tinted rust and Codex neutral gray.

- The library is a three-column `NavigationSplitView`: sidebar filters, the skill list, and the detail.
- Agents & Sync is a two-column split (sidebar and table), because the table needs the full width to compare agents side by side.
  Double-clicking a table row jumps back to All Skills with that skill selected and scrolled into view.
- The editor replaces the whole split view instead of sitting in the detail column.
  In the detail column the file list, editor and preview didn't fit and clipped the sidebar.
  Going back to the library, or selecting another skill, asks before discarding unsaved changes.
- New Skill, Import and Install are sheets driven by `LibraryModel.sheet`.
- Status text uses `Color.okText` and `Color.warningText` instead of system green and orange, which fail contrast as text in both appearances.

## SwiftUI pitfalls

- In a `List(selection:)`, `.tag` must be the outermost modifier on the row.
  With `.badge` (or similar) applied after `.tag`, the list can't find the tag and clicks silently select nothing.
- `List` on macOS wants an optional selection binding; the sidebar wraps the non-optional `filter` in a `Binding<SidebarFilter?>` that ignores `nil`.
- Buttons inside `Table` cells lose their chrome and look like plain text unless they get an explicit `.buttonStyle(.bordered)`.
- Content that should change color on a selected row reads `\.backgroundProminence`; `AgentBadge` switches to white on the accent color.
- A list that was just created has no rows laid out in `onAppear`, so `ScrollViewProxy.scrollTo` has to wait one run loop turn.
- Growing the skill list (for example turning on built-in skills) logs "Application performed a reentrant operation in its NSTableView delegate".
  It still appears with plain `Text` rows and no modifiers, and goes away only when the list has no selection, so it comes from SwiftUI's `List(selection:)` itself; Apple's forums have no fix ([thread](https://developer.apple.com/forums/thread/735378)).
  Don't spend time chasing it in our row code.
- Large `Table` builders with `ForEach` over columns hit "unable to type-check"; write each column out with an explicit `(skill: Skill)` parameter.

## Testing against a sandbox

Core behavior is covered by `swift test`, which uses a temporary home folder and never touches real skills.
For end-to-end checks, launch the app against a sandbox instead of your real folders:

```bash
open -n --env CLAUDE_CONFIG_DIR=/path/to/sandbox/claude --env CODEX_HOME=/path/to/sandbox/codex build/SkillsManager.app
```

Debug builds also read `SKILLS_MANAGER_APPEARANCE=light` or `dark` to force an appearance without changing system settings; release builds ignore it.
`ImportSourceStore` doesn't follow the sandbox, so a sandboxed import still writes to the real `import-sources.json`; move that file aside afterwards.
When driving the app with computer-use tools, background clicks don't reach the sidebar outline, so use full-screen control for sidebar interactions.
