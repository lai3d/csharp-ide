import Foundation

/// An expanded LSP snippet: plain text plus tab stops (`$1`, `${2:default}`, … then `$0`).
public struct Snippet: Sendable, Hashable {
    public let text: String
    /// UTF-16 ranges in `text`, in visiting order; the last is `$0` (or the end of the text).
    public let stops: [NSRange]

    public init(text: String, stops: [NSRange]) {
        self.text = text
        self.stops = stops
    }

    /// Parses LSP snippet syntax: `$n`, `${n}`, `${n:placeholder}` (nestable), `${n|a,b|}`
    /// (first choice), `$0`, and `\` escapes. Only the first occurrence of a stop is kept.
    public static func parse(_ snippet: String) -> Snippet {
        let chars = Array(snippet)
        var output = ""
        var length = 0  // UTF-16 length of output
        var stops: [Int: NSRange] = [:]
        var i = 0

        func append(_ c: Character) {
            output.append(c)
            length += c.utf16.count
        }

        func readNumber() -> Int? {
            var digits = ""
            while i < chars.count, chars[i].isNumber { digits.append(chars[i]); i += 1 }
            return Int(digits)
        }

        /// Parses until an unescaped "}" at this nesting level (consumed), or the end.
        func parseBody(untilBrace: Bool) {
            while i < chars.count {
                let c = chars[i]
                if c == "\\", i + 1 < chars.count, "$}\\,|".contains(chars[i + 1]) {
                    // Only these are escapable; any other backslash is literal (e.g. "\n" in Go strings).
                    append(chars[i + 1])
                    i += 2
                } else if untilBrace, c == "}" {
                    i += 1
                    return
                } else if c == "$", i + 1 < chars.count, chars[i + 1].isNumber {
                    i += 1
                    if let n = readNumber(), stops[n] == nil { stops[n] = NSRange(location: length, length: 0) }
                } else if c == "$", i + 1 < chars.count, chars[i + 1] == "{" {
                    i += 2
                    guard let n = readNumber() else { append("$"); continue }
                    let start = length
                    if i < chars.count, chars[i] == ":" {
                        i += 1
                        parseBody(untilBrace: true)
                    } else if i < chars.count, chars[i] == "|" {
                        // Choices: keep the first one.
                        i += 1
                        var choice = ""
                        while i < chars.count, chars[i] != "," && chars[i] != "|" { choice.append(chars[i]); i += 1 }
                        while i < chars.count, chars[i] != "}" { i += 1 }
                        i += 1
                        choice.forEach(append)
                    } else if i < chars.count, chars[i] == "}" {
                        i += 1
                    }
                    if stops[n] == nil { stops[n] = NSRange(location: start, length: length - start) }
                } else {
                    append(c)
                    i += 1
                }
            }
        }

        parseBody(untilBrace: false)
        var ordered = stops.filter { $0.key != 0 }.sorted { $0.key < $1.key }.map(\.value)
        ordered.append(stops[0] ?? NSRange(location: length, length: 0))
        return Snippet(text: output, stops: ordered)
    }

    /// Indents every line after the first (for insertion at an indented caret).
    public func indented(_ indent: String) -> Snippet {
        guard !indent.isEmpty, text.contains("\n") else { return self }
        let ns = text as NSString
        let extra = (indent as NSString).length
        var newlines: [Int] = []
        for i in 0..<ns.length where ns.character(at: i) == 0x0A { newlines.append(i) }
        let shifted = stops.map { stop -> NSRange in
            let before = newlines.filter { $0 < stop.location }.count
            let inside = newlines.filter { $0 >= stop.location && $0 < NSMaxRange(stop) }.count
            return NSRange(location: stop.location + before * extra, length: stop.length + inside * extra)
        }
        return Snippet(text: text.replacingOccurrences(of: "\n", with: "\n" + indent), stops: shifted)
    }
}

/// Built-in C# snippets, offered in completion by trigger word (Visual Studio's names where they exist).
/// Bodies indent with `\t`; the editor swaps in the configured indent unit.
public enum CSharpSnippets {
    public static let all: [(trigger: String, detail: String, body: String)] = [
        ("prop", "public T Name { get; set; }", "public ${1:int} ${2:Name} { get; set; }$0"),
        ("propg", "public T Name { get; private set; }", "public ${1:int} ${2:Name} { get; private set; }$0"),
        ("propi", "public T Name { get; init; }", "public ${1:int} ${2:Name} { get; init; }$0"),
        ("propfull", "property with backing field", "private ${1:int} ${2:field};\n\npublic $1 ${3:Name}\n{\n\tget => $2;\n\tset => $2 = value;\n}$0"),
        ("ctor", "constructor", "public ${1:ClassName}(${2})\n{\n\t$0\n}"),
        ("class", "class Name { … }", "public class ${1:Name}\n{\n\t$0\n}"),
        ("record", "record Name(…);", "public record ${1:Name}(${2:string Value});$0"),
        ("interface", "interface IName { … }", "public interface ${1:IName}\n{\n\t$0\n}"),
        ("struct", "struct Name { … }", "public struct ${1:Name}\n{\n\t$0\n}"),
        ("enum", "enum Name { … }", "public enum ${1:Name}\n{\n\t${2:First},\n\t$0\n}"),
        ("method", "public void Name(…) { … }", "public ${1:void} ${2:Name}(${3})\n{\n\t$0\n}"),
        ("async", "public async Task Name(…) { … }", "public async Task ${1:Name}Async(${2})\n{\n\t$0\n}"),
        ("svm", "static void Main(string[] args)", "static void Main(string[] args)\n{\n\t$0\n}"),
        ("cw", "Console.WriteLine(…);", "Console.WriteLine($1);$0"),
        ("for", "for (int i = 0; i < n; i++) { … }", "for (int ${1:i} = 0; $1 < ${2:length}; $1++)\n{\n\t$0\n}"),
        ("forr", "reverse for loop", "for (int ${1:i} = ${2:length} - 1; $1 >= 0; $1--)\n{\n\t$0\n}"),
        ("foreach", "foreach (var item in items) { … }", "foreach (var ${1:item} in ${2:items})\n{\n\t$0\n}"),
        ("if", "if (…) { … }", "if (${1:true})\n{\n\t$0\n}"),
        ("else", "else { … }", "else\n{\n\t$0\n}"),
        ("while", "while (…) { … }", "while (${1:true})\n{\n\t$0\n}"),
        ("do", "do { … } while (…);", "do\n{\n\t$0\n} while (${1:true});"),
        ("switch", "switch (…) { case …: }", "switch (${1:value})\n{\n\tcase ${2:0}:\n\t\t$0\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}"),
        ("try", "try { … } catch (Exception) { … }", "try\n{\n\t$1\n}\ncatch (${2:Exception} ${3:ex})\n{\n\t$0\n}"),
        ("tryf", "try { … } finally { … }", "try\n{\n\t$1\n}\nfinally\n{\n\t$0\n}"),
        ("using", "using (…) { … }", "using (${1:var resource = ${2:Create()}})\n{\n\t$0\n}"),
        ("lock", "lock (…) { … }", "lock (${1:this})\n{\n\t$0\n}"),
        ("fact", "[Fact] test (xUnit)", "[Fact]\npublic void ${1:Name}()\n{\n\t$0\n}"),
        ("theory", "[Theory] test (xUnit)", "[Theory]\n[InlineData(${2:1})]\npublic void ${1:Name}(${3:int value})\n{\n\t$0\n}"),
        ("test", "[Test] test (NUnit)", "[Test]\npublic void ${1:Name}()\n{\n\t$0\n}"),
        ("testm", "[TestMethod] test (MSTest)", "[TestMethod]\npublic void ${1:Name}()\n{\n\t$0\n}"),
        ("exception", "custom exception class", "public class ${1:My}Exception : Exception\n{\n\tpublic $1Exception() { }\n\tpublic $1Exception(string message) : base(message) { }\n\tpublic $1Exception(string message, Exception inner) : base(message, inner) { }\n}$0"),
    ]

    /// Completion items for snippets whose trigger matches `prefix` (fuzzy, needs ≥ 2 chars).
    public static func completions(matching prefix: String) -> [CompletionItem] {
        guard prefix.count >= 2 else { return [] }
        return all.filter { FuzzyMatch.matches(prefix, $0.trigger) }.map {
            CompletionItem(label: $0.trigger, kind: .snippet, detail: $0.detail,
                           insertText: Snippet.parse($0.body).text, sortText: "~" + $0.trigger, snippet: $0.body)
        }
    }
}
