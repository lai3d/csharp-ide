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
| 1.1 | ⬜ Language server | Replace gopls with `csharp-ls` (stdio); `.cs` language id; root = nearest `.sln`/`.slnx`/`.csproj`; find `dotnet` in `~/.dotnet`, `/usr/local/share/dotnet`, PATH | 0.6h |
| 1.2 | ⬜ C# highlighter | Regex lexer: verbatim/interpolated/raw strings, preprocessor, attributes, contextual keywords, XML doc comments | 0.5h |
| 1.3 | ⬜ dotnet build / run | Toolbar + .NET menu; parse MSBuild `file(line,col): error CS0000` into Problems | 0.5h |
| 1.4 | ⬜ Tests | `dotnet test` (xUnit / NUnit / MSTest) with TRX results: gutter ▶ / ✓ / ✗ per `[Fact]`/`[Test]`/`[TestMethod]` | 0.8h |
| 1.5 | ⬜ Debugger (netcoredbg DAP) | Replace Delve; download netcoredbg on first use (check osx-arm64 build availability), launch built dll | 1–1.5h |
| 1.6 | ⬜ Run configurations | Projects from the solution, launchSettings.json profiles, args, env, configuration | 0.5h |
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
