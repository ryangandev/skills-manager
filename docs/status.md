# Status

## Current state

The app builds with no warnings, and its 24 SkillsCore tests pass.
These were checked end to end in both light and dark mode:

- library
- detail
- Agents & Sync table
- full-window editor with save
- New Skill sheet
- Install sheet
- GitHub import (19 skills from `anthropics/skills`)

The repo is public at https://github.com/ryangandev/skills-manager under the MIT license.

## Next steps

- Check imported skills against their remembered source for updates; today the app only records the source.
- Support renaming a skill (folder and `name` together, for every agent that has it).
- Key `ImportSourceStore` by skills location as well as folder name, so a sandboxed or custom `CLAUDE_CONFIG_DIR` run doesn't share records with the real one.

## Not doing

- An Xcode project: SwiftPM plus `Scripts/package_app.sh` is enough for a personal tool.
- Installing Codex built-in skills into Claude Code from the UI: built-ins belong to Codex and can change under us.
