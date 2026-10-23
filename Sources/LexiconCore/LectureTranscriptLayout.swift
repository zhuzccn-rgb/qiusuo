import Foundation

/// Classroom transcripts are tens of thousands of characters. SwiftUI `Text` will
/// try to measure the whole string at once; split first so the view can lazy-load.
public enum LectureTranscriptLayout {
    public static let targetChars = 1_000
    public static let hardLimit = 2_000

    public static func chunks(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        if text.count <= hardLimit { return [text] }

        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let remaining = text.distance(from: start, to: text.endIndex)
            if remaining <= targetChars {
                out.append(String(text[start...]))
                break
            }
            let targetEnd = text.index(start, offsetBy: targetChars)
            let hardEnd = text.index(start, offsetBy: min(hardLimit, remaining))
            var end = breakIndex(in: text, from: targetEnd, start: start, hardEnd: hardEnd)
            if end <= start {
                end = targetEnd
            }
            out.append(String(text[start..<end]))
            start = end
        }
        return out
    }

    private static func breakIndex(
        in text: String,
        from targetEnd: String.Index,
        start: String.Index,
        hardEnd: String.Index
    ) -> String.Index {
        var i = targetEnd
        while i < hardEnd {
            let ch = text[i]
            if ch.isNewline || ch == "." || ch == "!" || ch == "?" || ch == "。" || ch == "！" || ch == "？" {
                return text.index(after: i)
            }
            i = text.index(after: i)
        }
        i = targetEnd
        while i > start {
            let ch = text[i]
            if ch.isWhitespace || ch == "." || ch == "。" {
                return text.index(after: i)
            }
            i = text.index(before: i)
        }
        return targetEnd
    }
}
