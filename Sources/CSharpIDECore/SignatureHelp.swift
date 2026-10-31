import Foundation

/// Parameter hints for the call around the caret (`textDocument/signatureHelp`).
public struct SignatureHelp: Sendable, Hashable {
    public struct Signature: Sendable, Hashable {
        public let label: String
        public let documentation: String?
        /// UTF-16 ranges of each parameter inside `label`.
        public let parameters: [NSRange]
        public let activeParameter: Int?
    }

    public let signatures: [Signature]
    public let activeSignature: Int
    /// Nil when the server didn't say (csharp-ls never does); see `resolvingActiveParameter`.
    public let activeParameter: Int?

    public var active: Signature? {
        signatures.indices.contains(activeSignature) ? signatures[activeSignature] : signatures.first
    }

    /// Range of the parameter being typed, within `active.label`.
    public var activeParameterRange: NSRange? {
        guard let active else { return nil }
        let index = active.activeParameter ?? activeParameter ?? 0
        return active.parameters.indices.contains(index) ? active.parameters[index] : nil
    }

    public static func parse(_ value: JSONValue) -> SignatureHelp? {
        let signatures = (value["signatures"]?.arrayValue ?? []).compactMap(parseSignature)
        guard !signatures.isEmpty else { return nil }
        return SignatureHelp(signatures: signatures,
                             activeSignature: value["activeSignature"]?.intValue ?? 0,
                             activeParameter: value["activeParameter"]?.intValue)
    }

    /// Fills in a missing active parameter by counting the call's top-level commas before the caret.
    public func resolvingActiveParameter(text: String, offset: Int) -> SignatureHelp {
        guard activeParameter == nil, active?.activeParameter == nil,
              let index = Self.argumentIndex(in: text, at: offset) else { return self }
        return SignatureHelp(signatures: signatures, activeSignature: activeSignature, activeParameter: index)
    }

    /// Zero-based argument index at UTF-16 `offset` inside the innermost unclosed `(` / `[` / `<`
    /// call, or nil if the caret isn't inside one. Skips nested brackets, strings and char literals
    /// on the way back (approximately: escapes are honoured, interpolation holes are not parsed).
    public static func argumentIndex(in text: String, at offset: Int) -> Int? {
        let units = Array(text.utf16.prefix(max(0, offset)))
        var commas = 0
        var depth = 0
        var i = units.count - 1
        let quote = UInt16(UInt8(ascii: "\"")), apostrophe = UInt16(UInt8(ascii: "'"))
        let backslash = UInt16(UInt8(ascii: "\\")), newline = UInt16(UInt8(ascii: "\n"))
        while i >= 0 {
            let c = units[i]
            switch c {
            case quote, apostrophe:
                // Walk back to the opening quote (not escaped), staying on this line.
                var j = i - 1
                while j >= 0, units[j] != newline {
                    if units[j] == c && (j == 0 || units[j - 1] != backslash) { break }
                    j -= 1
                }
                i = j
            case UInt16(UInt8(ascii: ")")), UInt16(UInt8(ascii: "]")), UInt16(UInt8(ascii: "}")):
                depth += 1
            case UInt16(UInt8(ascii: "(")), UInt16(UInt8(ascii: "[")), UInt16(UInt8(ascii: "{")):
                if depth == 0 { return c == UInt16(UInt8(ascii: "{")) ? nil : commas }
                depth -= 1
            case UInt16(UInt8(ascii: ",")):
                if depth == 0 { commas += 1 }
            case UInt16(UInt8(ascii: ";")):
                if depth == 0 { return nil }
            default:
                break
            }
            i -= 1
        }
        return nil
    }

    private static func parseSignature(_ value: JSONValue) -> Signature? {
        guard let label = value["label"]?.stringValue else { return nil }
        let ns = label as NSString
        var searchFrom = 0
        var ranges: [NSRange] = []
        for parameter in value["parameters"]?.arrayValue ?? [] {
            let paramLabel = parameter["label"]
            if let offsets = paramLabel?.arrayValue, offsets.count == 2,
               let start = offsets[0].intValue, let end = offsets[1].intValue {
                ranges.append(NSRange(location: start, length: max(0, end - start)))
            } else if let text = paramLabel?.stringValue {
                let found = ns.range(of: text, range: NSRange(location: searchFrom, length: ns.length - searchFrom))
                ranges.append(found.location == NSNotFound ? NSRange(location: 0, length: 0) : found)
                if found.location != NSNotFound { searchFrom = NSMaxRange(found) }
            }
        }
        let documentation = value["documentation"]?.stringValue ?? value["documentation"]?["value"]?.stringValue
        return Signature(label: label, documentation: documentation, parameters: ranges,
                         activeParameter: value["activeParameter"]?.intValue)
    }
}
