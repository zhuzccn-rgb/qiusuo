import Foundation

/// Line-oriented markdown used by lecture summaries.
/// Fenced code (``` / ~~~) stays one block so indentation and `#` inside it are literal.
public enum MarkdownSource {
    public enum Block: Equatable, Sendable {
        case heading(Int, String)
        case bullet(String)
        case paragraph(String)
        case code(language: String, text: String)
        case blank
    }

    public static func blocks(in source: String) -> [Block] {
        var out: [Block] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        while index < lines.count {
            let line = stripCR(String(lines[index]))
            if let fence = openingFence(line) {
                index += 1
                var code: [String] = []
                while index < lines.count {
                    let next = stripCR(String(lines[index]))
                    if closes(next, fence: fence) {
                        index += 1
                        break
                    }
                    code.append(next)
                    index += 1
                }
                out.append(.code(language: fence.language, text: code.joined(separator: "\n")))
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let last = out.last, case .blank = last {
                    index += 1
                    continue
                }
                out.append(.blank)
                index += 1
                continue
            }
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let rest = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
                out.append(.heading(min(3, hashes.count), rest))
                index += 1
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                out.append(.bullet(String(trimmed.dropFirst(2))))
                index += 1
                continue
            }
            out.append(.paragraph(trimmed))
            index += 1
        }
        return out
    }

    private struct Fence {
        var marker: Character
        var count: Int
        var language: String
    }

    private static func openingFence(_ line: String) -> Fence? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        var count = 0
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex, trimmed[cursor] == marker {
            count += 1
            cursor = trimmed.index(after: cursor)
        }
        guard count >= 3 else { return nil }
        let info = trimmed[cursor...].trimmingCharacters(in: .whitespaces)
        if marker == "`", info.contains("`") { return nil }
        let language = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return Fence(marker: marker, count: count, language: language)
    }

    private static func closes(_ line: String, fence: Fence) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= fence.count else { return false }
        return trimmed.allSatisfy { $0 == fence.marker }
    }

    private static func stripCR(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }
}
