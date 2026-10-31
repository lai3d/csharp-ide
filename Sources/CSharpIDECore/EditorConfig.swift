import Foundation

/// Resolves `.editorconfig` properties for a file (https://editorconfig.org): files from the
/// file's folder upward until one says `root = true`; nearer files and later sections win.
public enum EditorConfig {
    public struct Section: Sendable, Hashable {
        public var glob: String
        public var properties: [String: String]
    }

    public struct File: Sendable, Hashable {
        public var isRoot = false
        public var sections: [Section] = []
    }

    /// Indentation the editor and the formatter should use (nil = not specified).
    public struct Indentation: Sendable, Hashable {
        public var insertSpaces: Bool?
        public var size: Int?
    }

    public static func parse(_ text: String) -> File {
        var file = File()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                file.sections.append(Section(glob: String(line.dropFirst().dropLast()), properties: [:]))
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let comment = value.range(of: " #") ?? value.range(of: " ;") {
                value = value[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            if file.sections.isEmpty {
                if key == "root" { file.isRoot = value.lowercased() == "true" }
            } else {
                file.sections[file.sections.count - 1].properties[key] = value
            }
        }
        return file
    }

    /// Properties for `file` (keys lowercased). `read` returns a folder's .editorconfig text, if any.
    public static func properties(for file: URL,
                                  read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) })
        -> [String: String] {
        // Collect nearest-first, then apply farthest-first so nearer files override.
        var chain: [(dir: String, file: File)] = []
        // String paths: URL("/").deletingLastPathComponent() is "/.." on some Foundation versions,
        // which would walk upward forever.
        var dir = (file.path as NSString).deletingLastPathComponent
        while !dir.isEmpty {
            if let text = read(URL(fileURLWithPath: (dir as NSString).appendingPathComponent(".editorconfig"))) {
                let parsed = parse(text)
                chain.append((dir, parsed))
                if parsed.isRoot { break }
            }
            if dir == "/" { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        var result: [String: String] = [:]
        for (dirPath, config) in chain.reversed() {
            let base = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
            guard file.path.hasPrefix(base) else { continue }
            let relative = String(file.path.dropFirst(base.count))
            for section in config.sections where matches(section.glob, relativePath: relative) {
                result.merge(section.properties) { $1 }
            }
        }
        return result
    }

    public static func indentation(for file: URL,
                                   read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) })
        -> Indentation {
        let props = properties(for: file, read: read)
        var indentation = Indentation()
        switch props["indent_style"]?.lowercased() {
        case "space": indentation.insertSpaces = true
        case "tab": indentation.insertSpaces = false
        default: break
        }
        let size = props["indent_size"].flatMap { $0.lowercased() == "tab" ? props["tab_width"] : $0 }
        indentation.size = size.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            ?? props["tab_width"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        return indentation
    }

    /// EditorConfig globs: `*`, `**`, `?`, `[...]`, `{a,b}`. A glob without `/` matches the
    /// file name at any depth; one with `/` is relative to the .editorconfig's folder.
    public static func matches(_ glob: String, relativePath: String) -> Bool {
        var pattern = glob
        if pattern.hasPrefix("/") { pattern.removeFirst() } else if !pattern.contains("/") { pattern = "**/" + pattern }
        var regex = "^"
        var chars = Array(pattern)[...]
        var braceDepth = 0
        while let c = chars.popFirst() {
            switch c {
            case "*":
                if chars.first == "*" {
                    chars.removeFirst()
                    if chars.first == "/" {  // `**/` also matches no folder at all
                        chars.removeFirst()
                        regex += "(?:.*/)?"
                    } else {
                        regex += ".*"
                    }
                } else {
                    regex += "[^/]*"
                }
            case "?": regex += "[^/]"
            case "[":
                if let close = chars.firstIndex(of: "]") {
                    var body = String(chars[chars.startIndex..<close])
                    if body.hasPrefix("!") { body = "^" + body.dropFirst() }
                    regex += "[" + body.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                    chars = chars[chars.index(after: close)...]
                } else {
                    regex += "\\["
                }
            case "{":
                braceDepth += 1
                regex += "(?:"
            case "}" where braceDepth > 0:
                braceDepth -= 1
                regex += ")"
            case "," where braceDepth > 0: regex += "|"
            case "\\":
                if let next = chars.popFirst() { regex += NSRegularExpression.escapedPattern(for: String(next)) }
            default:
                regex += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        regex += "$"
        return relativePath.range(of: regex, options: .regularExpression) != nil
    }
}
