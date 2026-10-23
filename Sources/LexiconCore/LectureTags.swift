import Foundation

public enum LectureTags {
    public static func list(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func joined(_ tags: [String]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
            }
            if out.count >= 8 { break }
        }
        return out.joined(separator: ", ")
    }

    /// Pulls a trailing `标签：a, b` line out of an LLM summary.
    public static func splitSummary(_ text: String) -> (summary: String, tags: String) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        guard let last = lines.last else { return (text, "") }
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["标签：", "标签:", "Tags:", "tags:"]
        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else {
            return (text, "")
        }
        let tags = String(trimmed.dropFirst(prefix.count))
        lines.removeLast()
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        return (lines.joined(separator: "\n"), joined(list(tags)))
    }

    public static func extractFromMarkdown(_ markdown: String) -> String {
        var tags: [String] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                let heading = trimmed.drop(while: { $0 == "#" || $0 == " " })
                let cleaned = heading
                    .replacingOccurrences(of: "公式/定义", with: "")
                    .replacingOccurrences(of: "公式 / 定义", with: "")
                    .replacingOccurrences(of: "老师强调的易错点", with: "")
                    .replacingOccurrences(of: "关键概念", with: "")
                    .replacingOccurrences(of: "这堂课在讲什么", with: "")
                    .replacingOccurrences(of: "Key concepts", with: "")
                    .replacingOccurrences(of: "Definitions / formulas", with: "")
                    .replacingOccurrences(of: "What this lecture covered", with: "")
                    .replacingOccurrences(of: "Pitfalls", with: "")
                    .replacingOccurrences(of: "Homework / next week", with: "")
                    .replacingOccurrences(of: "Sources", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if cleaned.count >= 2, cleaned.count <= 16, !Self.isStructuralHeading(cleaned) {
                    tags.append(cleaned)
                }
            }
            tags.append(contentsOf: boldSpans(in: trimmed))
        }
        return joined(tags)
    }

    public static func merge(_ existing: String, _ extras: String) -> String {
        joined(list(existing) + list(extras))
    }

    private static func isStructuralHeading(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "key concepts", "definitions", "definitions / formulas", "formulas",
            "pitfalls", "homework", "homework / next week", "sources",
            "what this lecture covered", "what this lecture is about",
            "关键概念", "来源", "公式", "易错点"
        ].contains(key)
    }

    private static func boldSpans(in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*([^*]{2,16})\*\*"#) else { return [] }
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let span = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            return span.isEmpty ? nil : span
        }
    }
}
