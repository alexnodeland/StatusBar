# StatusBar — Claude Code Context

## Build & Test

```bash
make setup          # One-time: install tools + git hooks (brew bundle && lefthook install)
make build          # Dev build (arm64, fast)
make test           # Run unit tests
make lint           # SwiftLint --strict on Sources/ and Tests/
make format         # Auto-format with swift-format
make format-check   # Check formatting (fails if changes needed)
make check          # Lint + format check + tests (CI target)
make dev            # Build and open the app
make clean          # Remove build artifacts
```

## Architecture

- **Pure `swiftc` build** — no SPM or Xcode project. All `.swift` files in `Sources/` compile as a single compilation unit via `build.sh`.
- **Test harness** — `test.sh` compiles `Tests/` + most of `Sources/` into an XCTest bundle. It **excludes** `StatusBarApp.swift` (has `@main`) and `HotkeyManager.swift` (requires Carbon framework).
- **Settings** — `@AppStorage` for user preferences. `HistoryStore` uses file-based JSON in `~/Library/Application Support/StatusBar/`.
- **macOS 26** — targets macOS 26 with Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`, `.chromeBackground()`).

## Key Gotchas

- **SourceKit false positives** — SourceKit reports "Cannot find X in scope" for cross-file references because there's no SPM package. Ignore these; only `make build` matters.
- **test.sh exclusions** — when adding new source files that depend on Carbon or system frameworks, add them to the exclusion list in `test.sh`.
- **SwiftUI Color types** — `Color.secondary` works as a `Color`, but `.tertiary`/`.quaternary` are `ShapeStyle` only. Use `.gray` in `-> Color` return types.
- **AppDelegate access** — `@NSApplicationDelegateAdaptor` wraps the delegate in a proxy. `NSApp.delegate as? AppDelegate` returns nil. Use `ScriptBridge.service` for AppleScript commands.
- **No HotkeyManager in views** — don't reference `HotkeyManager` from views compiled in the test target. Use inline constants instead.

## Coding Conventions

- 4-space indentation, 140-char line length (see `.swift-format`)
- No SPM dependencies — everything is compiled directly with `swiftc`
- `@AppStorage` for simple settings, file-based JSON for complex data (history)
- SwiftLint + swift-format enforced in CI and pre-commit hooks
