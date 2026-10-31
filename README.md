# CSharpIDE

[![CI](https://github.com/lai3d/csharp-ide/actions/workflows/ci.yml/badge.svg)](https://github.com/lai3d/csharp-ide/actions/workflows/ci.yml)

A native macOS IDE for C# / .NET, written in Swift (SwiftUI + AppKit). Language intelligence comes
from [csharp-ls](https://github.com/razzmatazz/csharp-language-server) (Roslyn), debugging from
[netcoredbg](https://github.com/Samsung/netcoredbg).

> Early but usable: editing, navigation, refactoring, building, testing and debugging .NET projects.

## Features

**Editor**
- Tabs with independent buffers, undo and scroll; unsaved-changes prompts
- C# syntax highlighting (verbatim / interpolated / raw strings, attributes, preprocessor) refined by
  semantic tokens; inlay hints for parameter names and inferred types
- Line-number gutter with error/warning markers, Git change bars and code folding (⌥⌘← / ⌥⌘→)
- Occurrence highlights, current-line highlight, auto-indent with spaces (configurable)
- Auto-closing brackets and quotes, toggle comment (⌘/), move / duplicate lines, indent / outdent
- Snippets with Tab stops: `prop`, `propg`, `ctor`, `foreach`, `try`, `fact`, `theory`, `testm`, …
- Breadcrumbs (folder › file › namespace › type › member) above the editor
- Format on save and Format Document (⌥⇧F) via the Roslyn formatter

**Project**
- Sidebar file tree that follows changes on disk; `bin/` and `obj/` next to projects are hidden
- Projects and solutions (`.csproj`, `.sln`, `.slnx`) detected automatically
- Find in project (⇧⌘F): match case, whole word, regex
- Open Quickly (⌘P / ⇧⌘O): fuzzy file finder + workspace symbols; Outline sidebar for the current file
- Git: status badges, branch in the title bar, inline blame, staging and commits
- Multiple windows, one project each (⇧⌘N); integrated terminal (⌃`)

**Language (csharp-ls)**
- Live diagnostics: underlines, gutter dots, Problems panel
- Completion, hover docs, signature help while typing calls
- Go to definition (⌘-click / ⌃⌘J), implementation (⌥⌘J), type definition, back (⌃⌘←);
  find references (⇧⌘R), call hierarchy (⌃⌥H)
- Rename symbol across files (⌃⌘E), quick fixes and refactorings (⌥↩)

**Build, run, test & debug**
- `dotnet build` (⌘B), rebuild, clean, restore; MSBuild errors land in Problems, `File.cs(12,5)` links in Output
- Run configurations per runnable project: Debug/Release, `launchSettings.json` profile, arguments,
  environment → Run (⌘R), stop (⌘.)
- Tests via `dotnet test` (xUnit, NUnit, MSTest): Tests panel with messages and clickable stack traces,
  gutter ▶ / ✓ / ✗, run all (⌘U), project (⌃⌘U) or the test at the cursor (⌃⌥⌘U)
- Debugger (netcoredbg, ⌥⌘R): breakpoints (with conditions), step, call stack, variables, watches;
  debug the test at the cursor

See [ROADMAP.md](ROADMAP.md) for what's next.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 16 or later) to build from source
- The .NET SDK (8 or later): [dotnet.microsoft.com/download](https://dotnet.microsoft.com/download)
- csharp-ls: `dotnet tool install --global csharp-ls`
- netcoredbg for debugging: CSharpIDE offers to download it on first use (or set a path in Settings)

CSharpIDE looks for `dotnet` and `csharp-ls` on `PATH`, `~/.dotnet`, `~/.dotnet/tools`,
`/usr/local/share/dotnet` and Homebrew, and sets `DOTNET_ROOT` for them, so it works when launched
from Finder too. Paths can be overridden in Settings ▸ .NET Tools.

## Install

Download `CSharpIDE-vX.Y.Z.zip` from [Releases](https://github.com/lai3d/csharp-ide/releases), unzip, and move
`CSharpIDE.app` to Applications. Builds are ad-hoc signed (not notarized), so the first time
right-click the app and choose **Open** (or run `xattr -dr com.apple.quarantine CSharpIDE.app`).

## Build & run

```sh
swift run CSharpIDE Examples/hello     # run in debug, opening the example project
swift test                         # unit tests + csharp-ls / dotnet end-to-end tests
./scripts/bundle.sh                # build build/CSharpIDE.app + CSharpIDE.zip (release, ad-hoc signed)
open build/CSharpIDE.app
```

You can also open `Package.swift` in Xcode.

## Layout

| Path | What |
|---|---|
| `Sources/CSharpIDECore` | UI-independent core: LSP + DAP clients, C# highlighter, MSBuild / TRX parsing, project discovery, file tree |
| `Sources/CSharpIDE` | SwiftUI app: workspace state, editor view, sidebar, panels |
| `Tests/CSharpIDECoreTests` | swift-testing tests |
| `Examples/hello` | Small console project for trying things out |
| `scripts/` | `bundle.sh` (app bundle), `make-icon.swift` (regenerates `Resources/AppIcon.icns`) |
| `.github/workflows/` | CI (build, test, bundle) and tagged releases (`v*` → GitHub Release) |


## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.11.2 (MIT) — terminal emulation for the Terminal panel.
  Pinned before 1.12, whose Metal renderer needs Xcode's separately downloaded Metal toolchain.

## License

MIT — see [LICENSE](LICENSE).

## Releasing

Push a tag like `v0.2.0`; the Release workflow builds `CSharpIDE.zip` and attaches it to a GitHub
release. To ship a build that opens without Gatekeeper warnings you need, outside this repo:
an Apple Developer Program membership, a Developer ID Application certificate, and notarization
(`xcrun notarytool`) — then sign with that identity instead of `-` in `scripts/bundle.sh`.
