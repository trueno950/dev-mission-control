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
/// render the raw diff content, and `id` is a stable sequential identity so
/// lazy stacks never reuse rows by offset.
public struct DiffLine: Hashable, Sendable, Identifiable {
    public let id: Int
    public let kind: DiffLineKind
    public let text: String

    public init(id: Int, kind: DiffLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// Pure classifier for unified diffs.
public enum DiffParser {
    /// Splits a diff into classified lines. File metadata (`diff --git`,
    /// `index`, `+++`/`---` headers) is `meta`, never counted as an addition
    /// or removal; an empty input yields an empty list.
    public static func parse(_ diff: String) -> [DiffLine] {
        guard !diff.isEmpty else { return [] }
        return diff.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { offset, raw in
                let line = String(raw)
                return DiffLine(id: offset, kind: kind(of: line), text: line)
            }
    }

    private static func kind(of line: String) -> DiffLineKind {
        if line.hasPrefix("@@") { return .hunkHeader }
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .meta }
        if line.hasPrefix("diff --git") || line.hasPrefix("index ")
            || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("rename ") || line.hasPrefix("similarity ")
            || line.hasPrefix("old mode") || line.hasPrefix("new mode")
            || line.hasPrefix("Binary ") {
            return .meta
        }
        if line.hasPrefix("+") { return .addition }
        if line.hasPrefix("-") { return .removal }
        return .context
    }
}
