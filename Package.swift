// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CSharpIDE",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CSharpIDE", targets: ["CSharpIDE"]),
        .library(name: "CSharpIDECore", targets: ["CSharpIDECore"]),
    ],
    dependencies: [
        // Terminal emulation (VT100/xterm) + PTY process management for the Terminal panel.
        // 1.11.2: the last release before the Metal renderer, which needs the separately
        // downloaded Metal toolchain (Xcode 26+) to build.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.11.2"),
    ],
    targets: [
        // UI-independent pieces: LSP client, Go highlighter, text/position math, file tree.
        .target(name: "CSharpIDECore"),
        // SwiftUI/AppKit application shell.
        .executableTarget(name: "CSharpIDE", dependencies: ["CSharpIDECore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "CSharpIDECoreTests", dependencies: ["CSharpIDECore"]),
        .testTarget(name: "CSharpIDETests", dependencies: ["CSharpIDE", "CSharpIDECore"]),
    ]
)
