import Foundation

/// Joins SpeechAnalyzer (or dictation) segments into readable sentences.
public enum TranscriptStitch: Sendable {
    /// Gap between segment end and the next start that starts a new paragraph.
    public static let paragraphGap: TimeInterval = 1.8

    public static func shouldBreak(previousEnd: TimeInterval, start: TimeInterval) -> Bool {
        previousEnd > 0.2 && start.isFinite && (start - previousEnd) > paragraphGap
    }

    public static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.towardZero)))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func timestampPrefix(_ t: TimeInterval) -> String {
        "[\(clock(t))] "
    }

    public static func append(_ existing: String, _ incoming: String) -> String {
        let piece = incoming
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: CharacterSet.newlines)
            .trimmingCharacters(in: .whitespaces)
        guard !piece.isEmpty else { return existing }
        if existing.isEmpty { return piece }
        if existing.hasSuffix(" ") || existing.hasSuffix("\n") { return existing + piece }
        if let first = piece.first, ".,!?;:)]}%".contains(first) {
            return existing + piece
        }
        return existing + " " + piece
    }

    public static func paragraph(_ existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    /// Analyzer collect: keep the existing gap rule, stamp each new paragraph.
    public static func appendSegment(
        existing: String,
        incoming: String,
        start: TimeInterval,
        previousEnd: TimeInterval
    ) -> String {
        let piece = incoming
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: CharacterSet.newlines)
            .trimmingCharacters(in: .whitespaces)
        guard !piece.isEmpty else { return existing }

        let newParagraph = existing.isEmpty || shouldBreak(previousEnd: previousEnd, start: start)
        var text = existing
        if shouldBreak(previousEnd: previousEnd, start: start) {
            text = paragraph(text)
        }
        let stamped: String
        if newParagraph, start.isFinite {
            stamped = timestampPrefix(start) + piece
        } else {
            stamped = piece
        }
        return append(text, stamped)
    }
}
