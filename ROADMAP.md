# CSharpIDE Roadmap

Status: ✅ done · 🚧 in progress · ⬜ planned

Estimates are Claude Code session time.

Forked from GoIDE (same path RustIDE took), so the editor shell (tabs, gutter, folding,
search/replace, Git, terminal, LSP + DAP clients, multi-window, session restore) already exists.
The work is porting the language-specific layer to C# / .NET.

Toolchain on the dev Mac: .NET 10 SDK in `~/.dotnet` (dotnet-install.sh, no sudo),
`csharp-ls` 0.28 as a global dotnet tool in `~/.dotnet/tools`.

## Phase 0 — Fork

| # | Item | Notes | Est. |
|---|---|---|---|
| 0.1 | ✅ Fork GoIDE → CSharpIDE | Rename targets, bundle ID `io.github.lai3d.csharpide`, `dotnet new console` example | 0.1h |

## Phase 1 — Port to the .NET toolchain

| # | Item | Notes | Est. |
|---|---|---|---|
| 1.1 | ✅ Language server | `csharp-ls` over stdio: diagnostics, completion, hover, definition, references, rename, outline, signature help (active parameter inferred client-side), folding, call hierarchy, semantic tokens, inlay hints, formatting; `dotnet` found in `~/.dotnet`, `/usr/local/share/dotnet`, Homebrew, PATH with `DOTNET_ROOT` set; new `.cs` files get namespace + class | 0.6h |
| 1.2 | ✅ C# highlighter | Regex lexer: verbatim / interpolated / raw (`"""`, `$$"""`) / UTF-8 strings, chars, number suffixes, preprocessor, attributes, generic calls, contextual keywords, `@ident`; semantic colors for csharp-ls types (properties, constants, escapes) | 0.5h |
| 1.3 | ✅ dotnet build / run | .NET menu + toolbar: Build ⌘B (solution, else the only project), Rebuild, Clean, Restore, Run ⌘R; MSBuild `File.cs(l,c): error CS…` → Problems for files csharp-ls hasn't reported; clickable `File.cs(l,c)` / `:line N` in Output; `bin`/`obj` next to projects hidden | 0.5h |
| 1.4 | ✅ Tests | `dotnet test` with console + TRX loggers: live ✓ / ✗ while running, exact outcomes / messages / stack traces from TRX; xUnit / NUnit / MSTest methods found in source → gutter ▶ / ✓ / ✗, run at caret (`--filter FullyQualifiedName=`), project, all; theory rows listed separately | 0.8h |
| 1.5 | 🚧 Debugger (netcoredbg DAP) | DAP over stdio; build → `msbuild -getProperty:TargetPath` → `dotnet <dll>` under netcoredbg; debug test at caret via `VSTEST_HOST_DEBUG` + attach; one-click download of netcoredbg 3.2.0 (osx-arm64) into Application Support. **Needs an end-to-end run against netcoredbg** | 1–1.5h |
| 1.6 | ✅ Run configurations | One per runnable project (Exe / Web / Worker SDK, test projects excluded); project, Debug/Release, `launchSettings.json` profile, args, env → `dotnet run --project … -- …` | 0.5h |
| 1.7 | ⬜ Snippets & settings | C# snippets (`prop`, `ctor`, `class`, `foreach`, …); dotnet / csharp-ls / netcoredbg path overrides | 0.4h |
| 1.8 | ⬜ CI & release | .NET in GitHub Actions, tagged `CSharpIDE-vX.Y.Z.zip`, app icon, IDE Toolbox catalog entry | 0.5h |

## Phase 2 — .NET-specific features

| # | Item | Notes | Est. |
|---|---|---|---|
| 2.1 | ⬜ Solution explorer | Projects / dependencies / NuGet packages from the `.sln` + `.csproj` | 0.6h |
| 2.2 | ⬜ NuGet | Search / add / update packages (`dotnet add package`, `dotnet list package --outdated`) | 0.6h |
| 2.3 | ⬜ Format | `dotnet format` / LSP formatting on save, `.editorconfig` respected | 0.3h |
| 2.4 | ⬜ Decompiled sources | Go to definition into metadata (csharp-ls `csharp/metadata`) in a read-only tab | 0.4h |
| 2.5 | ⬜ Coverage | `dotnet test --collect "XPlat Code Coverage"` (coverlet cobertura) | 0.5h |
| 2.6 | ⬜ Roslyn LSP option | Optional Microsoft.CodeAnalysis.LanguageServer backend for richer analyzers | 1h |

**User must do manually** (duration outside Claude's control): Apple Developer Program enrollment,
Developer ID certificate, notarization — only needed to ship a signed/notarized build to others.
