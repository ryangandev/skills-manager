# Docs

Use this page to find the section that answers your question, then read only that section.

| Question | Read |
| --- | --- |
| What is done, what is next, what is waiting on Ryan? | [status.md](status.md) |
| Where does a piece of code live? | [architecture.md: Code map](architecture.md#code-map) |
| How are skills found and grouped across agents? | [architecture.md: Scanning and sync status](architecture.md#scanning-and-sync-status) |
| How is SKILL.md read and written? | [architecture.md: SKILL.md parsing](architecture.md#skillmd-parsing) |
| How do install, link, copy and remove work? | [architecture.md: Install and remove](architecture.md#install-and-remove) |
| How does import from GitHub, a folder or a ZIP work? | [architecture.md: Import](architecture.md#import) |
| How does the app notice changes on disk? | [architecture.md: File watching](architecture.md#file-watching) |
| How are the library, editor and sheets laid out? | [architecture.md: UI structure](architecture.md#ui-structure) |
| Why does a SwiftUI control misbehave? | [architecture.md: SwiftUI pitfalls](architecture.md#swiftui-pitfalls) |
| How do I test without touching real skills? | [architecture.md: Testing against a sandbox](architecture.md#testing-against-a-sandbox) |

## Ownership and updates

Each fact lives in exactly one place; other places link to it instead of copying it.
`status.md` owns current state and next steps; delete items once they are resolved instead of archiving them.
`architecture.md` owns how each subsystem works and why, next to the code it describes.
Update the owning doc in the same commit as the code change.
Keep headings stable, because this table links to them.
A larger subsystem can get its own doc, as long as it is registered in this table.
The visual design lives in Claude Design: https://claude.ai/artifact/5aGFqfZkHt1sCUMvfodxnM.
