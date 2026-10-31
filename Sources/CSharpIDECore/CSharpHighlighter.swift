import Foundation

public enum SyntaxKind: Sendable, Hashable {
    case keyword, type, builtin, function, string, comment, number, preprocessor, attribute
}

public struct SyntaxToken: Sendable, Hashable {
    public let range: NSRange
    public let kind: SyntaxKind

    public init(range: NSRange, kind: SyntaxKind) {
        self.range = range
        self.kind = kind
    }
}

/// A fast, regex-based C# lexer for syntax highlighting; csharp-ls semantic tokens are layered
/// on top (types, members, parameters), so this only has to get the lexical structure right.
public enum CSharpHighlighter {
    public static let keywords: Set<String> = [
        "abstract", "as", "base", "break", "case", "catch", "checked", "class", "const", "continue",
        "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "finally", "fixed",
        "for", "foreach", "goto", "if", "implicit", "in", "interface", "internal", "is", "lock",
        "namespace", "new", "operator", "out", "override", "params", "private", "protected", "public",
        "readonly", "ref", "return", "sealed", "sizeof", "stackalloc", "static", "struct", "switch",
        "throw", "try", "typeof", "unchecked", "unsafe", "using", "virtual", "volatile", "while",
        // Contextual keywords (highlighting them everywhere is what most editors do).
        "add", "and", "alias", "allows", "ascending", "async", "await", "by", "descending", "equals",
        "extension", "field", "file", "from", "get", "global", "group", "init", "into", "join", "let",
        "managed", "nameof", "not", "notnull", "on", "or", "orderby", "partial", "record", "remove",
        "required", "scoped", "select", "set", "unmanaged", "value", "var", "when", "where", "with", "yield",
    ]

    public static let types: Set<String> = [
        "bool", "byte", "char", "decimal", "double", "dynamic", "float", "int", "long", "nint",
        "nuint", "object", "sbyte", "short", "string", "uint", "ulong", "ushort", "void",
    ]

    /// Literal-like keywords.
    public static let builtins: Set<String> = ["true", "false", "null", "this"]

    // Alternation order matters: comments and strings win over anything inside them.
    private static let regex = try! NSRegularExpression(pattern: [
        #"(?<comment>//[^\n]*|/\*[\s\S]*?(?:\*/|$(?![\s\S])))"#,
        #"(?<pre>^[ \t]*#[ \t]*[a-z]+\b[^\n]*)"#,
        // """raw""" (any quote count ≥ 3, optional $ prefixes); unterminated runs to the end
        #"(?<raw>\$*(?<q>"{3,})[\s\S]*?(?:\k<q>|$(?![\s\S])))"#,
        // @"verbatim" / $@"…" / @$"…": "" escapes, may span lines
        #"(?<verbatim>(?:\$+@|@\$+|@)"(?:""|[^"])*"?)"#,
        #"(?<string>\$*"(?:\\.|[^"\\\n])*"?(?:u8)?|'(?:\\.|[^'\\\n])*'?)"#,
        #"(?<number>\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?|\.\d[\d_]*(?:[eE][+-]?\d+)?)(?:[uU][lL]?|[lL][uU]?|[fFdDmM])?\b)"#,
        #"(?<ident>@?[\p{L}_][\p{L}\p{Nd}_]*)"#,
    ].joined(separator: "|"), options: [.anchorsMatchLines])

    public static func tokenize(_ text: String) -> [SyntaxToken] {
        let ns = text as NSString
        var tokens: [SyntaxToken] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            func has(_ name: String) -> Bool { match.range(withName: name).location != NSNotFound }
            let range = match.range
            if has("comment") {
                tokens.append(SyntaxToken(range: range, kind: .comment))
            } else if has("pre") {
                tokens.append(SyntaxToken(range: range, kind: .preprocessor))
            } else if has("raw") || has("verbatim") || has("string") {
                tokens.append(SyntaxToken(range: range, kind: .string))
            } else if has("number") {
                tokens.append(SyntaxToken(range: range, kind: .number))
            } else {
                let word = ns.substring(with: range)
                if word.hasPrefix("@") { return }  // @class: an identifier, not a keyword
                if keywords.contains(word) {
                    tokens.append(SyntaxToken(range: range, kind: .keyword))
                } else if types.contains(word) {
                    tokens.append(SyntaxToken(range: range, kind: .type))
                } else if builtins.contains(word) {
                    tokens.append(SyntaxToken(range: range, kind: .builtin))
                } else if isAttribute(ns, range: range) {
                    tokens.append(SyntaxToken(range: range, kind: .attribute))
                } else if isFollowedByCall(ns, at: NSMaxRange(range)) {
                    tokens.append(SyntaxToken(range: range, kind: .function))
                }
            }
        }
        return tokens
    }

    /// `Name(` or `Name<T, U>(` (a generic call / declaration).
    private static func isFollowedByCall(_ ns: NSString, at index: Int) -> Bool {
        var i = skipSpaces(ns, from: index)
        guard i < ns.length else { return false }
        if ns.character(at: i) == 0x28 { return true }  // (
        guard ns.character(at: i) == 0x3C else { return false }  // <
        var depth = 0
        while i < ns.length {
            switch ns.character(at: i) {
            case 0x3C: depth += 1
            case 0x3E:
                depth -= 1
                if depth == 0 {
                    let next = skipSpaces(ns, from: i + 1)
                    return next < ns.length && ns.character(at: next) == 0x28
                }
            case 0x0A, 0x3B, 0x7B, 0x7D, 0x28, 0x29, 0x3D: return false  // \n ; { } ( ) =
            default: break
            }
            i += 1
        }
        return false
    }

    /// The first name inside `[...]` at the start of an attribute list: `[Fact]`, `[assembly: X]`,
    /// `[Serializable, Obsolete("…")]` (each name after `[` or `,` at bracket depth 1 counts).
    private static func isAttribute(_ ns: NSString, range: NSRange) -> Bool {
        // Back over an optional `target:` and whitespace to the `[` / `,`.
        var i = range.location - 1
        while i >= 0, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i -= 1 }
        guard i >= 0 else { return false }
        let before = ns.character(at: i)
        if before == 0x3A {  // `assembly:` / `return:` targets
            i -= 1
            while i >= 0, isIdentifierUnit(ns.character(at: i)) { i -= 1 }
            while i >= 0, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i -= 1 }
            guard i >= 0 else { return false }
            return ns.character(at: i) == 0x5B && startsLine(ns, before: i)
        }
        if before == 0x2C {  // `, Name` inside `[A, Name]`: find the list's unmatched `[` on this line
            var depth = 0
            var j = i - 1
            while j >= 0, ns.character(at: j) != 0x0A {
                switch ns.character(at: j) {
                case 0x29, 0x5D: depth += 1  // ) ]
                case 0x28: depth -= 1  // (
                case 0x5B where depth == 0: i = j; j = 0  // found it
                case 0x5B: depth -= 1
                default: break
                }
                j -= 1
            }
            guard ns.character(at: i) == 0x5B else { return false }
        } else if before != 0x5B {  // [
            return false
        }
        // An attribute list starts its line (`[Fact]`) or follows `(` / `,` for parameters.
        guard startsLine(ns, before: i) || precededBy(ns, before: i, oneOf: [0x28, 0x2C]) else { return false }
        // …and is not an indexer: the name is followed by `]`, `(`, `,` or `:`-less end.
        let next = skipSpaces(ns, from: NSMaxRange(range))
        guard next < ns.length else { return false }
        return [0x5D, 0x28, 0x2C, 0x2E].contains(ns.character(at: next))  // ] ( , .
    }

    private static func startsLine(_ ns: NSString, before index: Int) -> Bool {
        var i = index - 1
        while i >= 0 {
            let c = ns.character(at: i)
            if c == 0x0A { return true }
            if c == 0x5D { return true }  // `[A][B]`
            if c != 0x20 && c != 0x09 { return false }
            i -= 1
        }
        return true
    }

    private static func precededBy(_ ns: NSString, before index: Int, oneOf units: [unichar]) -> Bool {
        var i = index - 1
        while i >= 0, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i -= 1 }
        return i >= 0 && units.contains(ns.character(at: i))
    }

    private static func isIdentifierUnit(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    private static func skipSpaces(_ ns: NSString, from index: Int) -> Int {
        var i = index
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        return i
    }
}
