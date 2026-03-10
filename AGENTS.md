# AGENTS.md

Instructions for coding agents working on this repo.

## Validating Changes
- Run the swift-build skill
- Run the swift-format skill
- Run the swift-test skill
- Keep `SPEC.md` up-to-date when making changes.
- You don't need to run swift-format and swift-test to validate changes to markdown files.

## General
- Use mise for dependency management
- Follow established patterns in the codebase where possible.
- Follow best-practices for the targeted language and platform.
- Keep edits small and focused; avoid unrelated refactors.
- Keep files ASCII unless the file already uses Unicode.
- Use a consistent project structure, with folder layout determined by features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Add code comments and documentation comments as needed.
- When trying to access Apple documentation, use the `sosumi` skill.

## Swift
- Swift 6.2 or later, using modern Swift concurrency.
- Use the `swift-concurrency` skill for Swift concurrency guidance.
- Always mark @Observable classes with @MainActor.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using replacing("hello", with: "world") with strings rather than replacingOccurrences(of: "hello", with: "world").
- Prefer modern Foundation API, for example URL.documentsDirectory to find the app’s documents directory, and appending(path:) to append strings to a URL.
- Never use C-style number formatting such as Text(String(format: "%.2f", abs(myNumber))); always use Text(abs(change), format: .number.precision(.fractionLength(2))) instead.
- Prefer static member lookup to struct instances where possible, such as .circle rather than Circle(), and .borderedProminent rather than BorderedProminentButtonStyle().
- Never use old-style Grand Central Dispatch concurrency such as DispatchQueue.main.async(). If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using localizedStandardContains() as opposed to contains().
- Avoid force unwraps and force try unless it is unrecoverable.


## Tools
- Prefer `ast-grep` for syntax-aware searches; only use `rg` for plain-text matching when needed.
- Use the `gh` CLI for GitHub operations when available (e.g., creating repos and pushing).
