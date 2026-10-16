import Foundation

/// A deliberately small TOML subset, enough for vimouse's config and nothing more:
/// `[section]` headers, `key = value` with strings, integers, floats, booleans and
/// one-line arrays of those, `#` comments. No dotted keys, no multi-line strings,
/// no inline tables, no dates. Keeps VimouseCore free of dependencies.
public enum TOMLValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])

    public var string: String? { if case .string(let s) = self { return s } else { return nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var double: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    public var int: Int? { if case .int(let i) = self { return i } else { return nil } }
    public var strings: [String]? {
        switch self {
        case .string(let s): return [s]
        case .array(let a): return a.compactMap(\.string).count == a.count ? a.compactMap(\.string) : nil
        default: return nil
        }
    }
}

public struct TOMLError: Error, CustomStringConvertible, Equatable {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }
}

/// Parsed document: section name ("" for the root) -> key -> value.
public typealias TOMLTable = [String: [String: TOMLValue]]

public enum TOML {
    public static func parse(_ text: String) throws -> TOMLTable {
        var table: TOMLTable = ["": [:]]
        var section = ""
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNo = i + 1
            let line = stripComment(String(raw)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count >= 3 else { throw TOMLError(line: lineNo, message: "bad section header") }
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if table[section] == nil { table[section] = [:] }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { throw TOMLError(line: lineNo, message: "expected key = value") }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let rhs = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw TOMLError(line: lineNo, message: "empty key") }
            table[section, default: [:]][key] = try parseValue(rhs, line: lineNo)
        }
        return table
    }

    private static func stripComment(_ line: String) -> String {
        var inString = false
        var out = ""
        var prev: Character = " "
        for c in line {
            if c == "\"", prev != "\\" { inString.toggle() }
            if c == "#", !inString { break }
            out.append(c)
            prev = c
        }
        return out
    }

    private static func parseValue(_ s: String, line: Int) throws -> TOMLValue {
        if s.hasPrefix("\"") {
            guard s.count >= 2, s.hasSuffix("\"") else { throw TOMLError(line: line, message: "unterminated string") }
            return .string(unescape(String(s.dropFirst().dropLast())))
        }
        if s.hasPrefix("[") {
            guard s.hasSuffix("]") else { throw TOMLError(line: line, message: "unterminated array") }
            let inner = String(s.dropFirst().dropLast())
            return .array(try splitArray(inner).map { try parseValue($0, line: line) })
        }
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        let cleaned = s.replacingOccurrences(of: "_", with: "")
        if let i = Int(cleaned) { return .int(i) }
        if let d = Double(cleaned) { return .double(d) }
        throw TOMLError(line: line, message: "cannot parse value: \(s)")
    }

    /// Splits "a, \"b, c\", 3" on top-level commas.
    private static func splitArray(_ s: String) throws -> [String] {
        var items: [String] = []
        var cur = ""
        var inString = false
        var depth = 0
        var prev: Character = " "
        for c in s {
            if c == "\"", prev != "\\" { inString.toggle() }
            if !inString {
                if c == "[" { depth += 1 }
                if c == "]" { depth -= 1 }
                if c == ",", depth == 0 {
                    items.append(cur.trimmingCharacters(in: .whitespaces))
                    cur = ""
                    prev = c
                    continue
                }
            }
            cur.append(c)
            prev = c
        }
        let last = cur.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { items.append(last) }
        return items.filter { !$0.isEmpty }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\n", with: "\n")
    }
}
