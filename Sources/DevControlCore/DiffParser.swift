import Foundation

/// Classification of one unified-diff line for the colored diff sheet (S20):
/// additions render green, removals red, hunk headers accent-colored, and
/// file metadata dimmed.
public enum DiffLineKind: Hashable, Sendable {
    case addition
    case removal
    case hunkHeader
    case meta
    case context
}

/// One parsed unified-diff line. `text` keeps its leading sign so the UI can
/// render the raw diff content, and `id` is a deterministic content identity
/// (FNV-1a of the text plus an occurrence counter) so lazy stacks never
/// identify rows by position.
public struct DiffLine: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: DiffLineKind
    public let text: String

    public init(id: String, kind: DiffLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// Pure classifier for unified diffs.
public enum DiffParser {
    /// Splits a diff into classified lines. Classification tracks the hunk
    /// state: `+++`/`---` are metadata only before the first `@@` of a file
    /// section, while inside a hunk every `+`/`-` line is an addition or
    /// removal even when its content starts with extra signs. An empty input
    /// yields an empty list.
    public static func parse(_ diff: String) -> [DiffLine] {
        guard !diff.isEmpty else { return [] }
        var lines: [DiffLine] = []
        var inHunk = false
        var occurrences: [String: Int] = [:]
        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(raw)
            let kind = kind(of: text, inHunk: &inHunk)
            let occurrence = occurrences[text, default: 0]
            occurrences[text] = occurrence + 1
            lines.append(DiffLine(id: "\(fnv1a(text))-\(occurrence)", kind: kind, text: text))
        }
        return lines
    }

    private static func kind(of line: String, inHunk: inout Bool) -> DiffLineKind {
        if line.hasPrefix("@@") {
            inHunk = true
            return .hunkHeader
        }
        if line.hasPrefix("diff --git") || line.hasPrefix("index ")
            || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("rename ") || line.hasPrefix("similarity ")
            || line.hasPrefix("old mode") || line.hasPrefix("new mode")
            || line.hasPrefix("Binary ") {
            inHunk = false
            return .meta
        }
        if inHunk {
            if line.hasPrefix("+") { return .addition }
            if line.hasPrefix("-") { return .removal }
            return .context
        }
        // Before any hunk, +++/--- are file headers; bare signs still classify
        // as additions/removals so partial diffs stay readable.
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .meta }
        if line.hasPrefix("+") { return .addition }
        if line.hasPrefix("-") { return .removal }
        return .context
    }

    /// Deterministic 64-bit FNV-1a hash so identities survive re-parsing.
    private static func fnv1a(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
