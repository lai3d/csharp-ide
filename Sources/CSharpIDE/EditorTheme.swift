import AppKit
import CSharpIDECore

/// User-adjustable editor settings (stored in UserDefaults, edited in Settings).
struct EditorSettings: Equatable {
    static let fontSizeKey = "editorFontSize"
    static let tabWidthKey = "editorTabWidth"
    static let insertSpacesKey = "editorInsertSpaces"

    var fontSize: Double = 13
    var tabWidth: Int = 4
    /// C# convention: indent with spaces (Tab, Return, ⌘], snippets).
    var insertSpaces = true

    /// One level of indentation.
    var indentUnit: String { insertSpaces ? String(repeating: " ", count: tabWidth) : "\t" }
}

@MainActor
enum EditorTheme {
    static func font(_ settings: EditorSettings) -> NSFont {
        .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
    }

    static func paragraphStyle(_ settings: EditorSettings) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font(settings)]).width
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * CGFloat(settings.tabWidth)  // for files that do use tabs
        return style
    }

    static func baseAttributes(_ settings: EditorSettings) -> [NSAttributedString.Key: Any] {
        [.font: font(settings), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle(settings)]
    }

    /// Colors for what only csharp-ls knows (the regex lexer handles keywords, strings, …).
    static func color(forSemantic type: String, modifiers: Set<String>) -> NSColor? {
        switch type {
        case "namespace": .secondaryLabelColor
        case "class", "struct", "interface", "enum", "typeParameter", "delegate", "recordClass",
             "recordStruct", "type": .systemTeal
        case "parameter": .systemBrown
        case "method", "extensionMethod", "function": .systemBlue
        case "property", "field", "event": .systemPurple
        case "constant", "enumMember": .systemIndigo
        case "stringEscapeCharacter": .systemRed
        default: nil
        }
    }

    // System colors adapt to light and dark mode automatically.
    static func color(for kind: SyntaxKind) -> NSColor {
        switch kind {
        case .keyword: .systemPink
        case .type: .systemPink  // int, string, void: keywords in C#
        case .builtin: .systemPink
        case .preprocessor: .systemGray
        case .attribute: .systemTeal
        case .function: .systemBlue
        case .string: .systemOrange
        case .number: .systemIndigo
        case .comment: .systemGreen
        }
    }
}
