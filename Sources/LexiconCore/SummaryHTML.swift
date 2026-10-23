import Foundation

/// Turns a lecture summary into HTML whose `$…$` / `\[…\]` MathJax can typeset.
public enum SummaryHTML {
    public static func containsMath(_ source: String) -> Bool {
        guard source.contains("$") || source.contains("\\") else { return false }
        for block in MarkdownSource.blocks(in: source) {
            let text: String
            switch block {
            case .heading(_, let value), .bullet(let value), .paragraph(let value):
                text = value
            case .code, .blank:
                continue
            }
            guard text.contains("$") || text.contains("\\") else { continue }
            if protect(text).hasMath { return true }
        }
        return false
    }

    public static func document(markdown: String) -> String {
        let body = htmlDocumentBody(markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' file:; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        html, body { margin: 0; background: transparent; color: CanvasText;
          font: 13px/1.45 -apple-system, BlinkMacSystemFont, sans-serif; }
        h1 { font-size: 22px; font-weight: 600; margin: 0 0 8px; }
        h2 { font-size: 18px; font-weight: 600; margin: 12px 0 6px; }
        h3 { font-size: 15px; font-weight: 600; margin: 10px 0 4px; }
        p { margin: 0 0 8px; }
        ul { margin: 0 0 8px; padding-left: 1.2em; }
        code { font-family: ui-monospace, Menlo, monospace; font-size: 12px; }
        pre { margin: 0 0 8px; padding: 8px 10px; border-radius: 6px; overflow-x: auto;
          white-space: pre-wrap;
          background: color-mix(in srgb, CanvasText 7%, transparent); }
        pre code { white-space: pre-wrap; }
        .lang { font: 11px/1.3 -apple-system, BlinkMacSystemFont, sans-serif; margin: 0 0 4px; opacity: 0.65; }
        .display { margin: 8px 0; }
        </style>
        <script>
        window.MathJax = {
          tex: {
            inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
            displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']]
          },
          svg: { fontCache: 'local' },
          startup: {
            ready() {
              MathJax.startup.defaultReady();
              MathJax.startup.promise.then(report);
            }
          }
        };
        function report() {
          const h = Math.ceil(document.documentElement.scrollHeight);
          window.webkit.messageHandlers.height.postMessage(h);
        }
        window.addEventListener('resize', report);
        </script>
        <script src="tex-svg.js"></script>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func htmlDocumentBody(_ markdown: String) -> String {
        var html = ""
        var prose: [String] = []
        func flush() {
            guard !prose.isEmpty else { return }
            let protected = protect(prose.joined(separator: "\n"))
            html += htmlBody(protected.text, slots: protected.slots)
            prose.removeAll(keepingCapacity: true)
        }
        for block in MarkdownSource.blocks(in: markdown) {
            switch block {
            case .code(let language, let text):
                flush()
                html += codeHTML(language: language, text: text)
            case .heading(let level, let text):
                prose.append(String(repeating: "#", count: max(level, 1)) + " " + text)
            case .bullet(let text):
                prose.append("- " + text)
            case .paragraph(let text):
                prose.append(text)
            case .blank:
                prose.append("")
            }
        }
        flush()
        return html
    }

    private static func codeHTML(language: String, text: String) -> String {
        let label = language.isEmpty ? "" : "<div class=\"lang\">\(escape(language))</div>"
        return "<pre>\(label)<code>\(escape(text))</code></pre>"
    }

    static func protect(_ source: String) -> (text: String, slots: [String], hasMath: Bool) {
        var slots: [String] = []
        var out = ""
        var hasMath = false
        let chars = Array(source)
        var i = 0

        func slot(_ latex: String, display: Bool) -> String {
            hasMath = true
            let escaped = escape(latex)
            let html = display
                ? "<div class=\"display\">\\[\(escaped)\\]</div>"
                : "\\(\(escaped)\\)"
            slots.append(html)
            return "\u{E000}\(slots.count - 1)\u{E001}"
        }

        while i < chars.count {
            if chars[i] == "`" {
                var j = i + 1
                while j < chars.count, chars[j] != "`" { j += 1 }
                let end = min(j + 1, chars.count)
                out += String(chars[i..<end])
                i = end
                continue
            }
            if i + 1 < chars.count, chars[i] == "$", chars[i + 1] == "$" {
                if let end = find(chars, from: i + 2, marker: ["$", "$"]) {
                    let latex = String(chars[(i + 2)..<end])
                    out += "\n" + slot(latex, display: true) + "\n"
                    i = end + 2
                    continue
                }
            }
            if i + 1 < chars.count, chars[i] == "\\", chars[i + 1] == "[" {
                if let end = find(chars, from: i + 2, marker: ["\\", "]"]) {
                    let latex = String(chars[(i + 2)..<end])
                    out += "\n" + slot(latex, display: true) + "\n"
                    i = end + 2
                    continue
                }
            }
            if i + 1 < chars.count, chars[i] == "\\", chars[i + 1] == "(" {
                if let end = find(chars, from: i + 2, marker: ["\\", ")"]) {
                    let latex = String(chars[(i + 2)..<end])
                    out += slot(latex, display: false)
                    i = end + 2
                    continue
                }
            }
            if chars[i] == "$", i == 0 || chars[i - 1] != "\\" {
                if i + 1 < chars.count, chars[i + 1] != "$", chars[i + 1] != " ", chars[i + 1] != "\n", !chars[i + 1].isNumber {
                    if let end = findInlineDollar(chars, from: i + 1) {
                        let latex = String(chars[(i + 1)..<end])
                        out += slot(latex, display: false)
                        i = end + 1
                        continue
                    }
                }
            }
            if chars[i] == "\\", let end = takeCommand(chars, from: i), end > i {
                out += slot(String(chars[i..<end]), display: false)
                i = end
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return (out, slots, hasMath)
    }

    static func htmlBody(_ text: String, slots: [String]) -> String {
        var html = ""
        var bullets: [String] = []
        func flushBullets() {
            guard !bullets.isEmpty else { return }
            html += "<ul>" + bullets.map { "<li>\($0)</li>" }.joined() + "</ul>"
            bullets = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushBullets()
                continue
            }
            if let slot = loneSlot(line, slots: slots) {
                flushBullets()
                html += slot
                continue
            }
            if line.hasPrefix("#") {
                flushBullets()
                let hashes = line.prefix(while: { $0 == "#" })
                let level = min(3, hashes.count)
                let rest = inline(line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces), slots: slots)
                html += "<h\(level)>\(rest)</h\(level)>"
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                bullets.append(inline(String(line.dropFirst(2)), slots: slots))
                continue
            }
            flushBullets()
            html += "<p>\(inline(line, slots: slots))</p>"
        }
        flushBullets()
        return html
    }

    private static func loneSlot(_ line: String, slots: [String]) -> String? {
        guard line.hasPrefix("\u{E000}"), line.hasSuffix("\u{E001}"),
              let n = Int(line.dropFirst().dropLast()), n >= 0, n < slots.count,
              slots[n].hasPrefix("<div") else { return nil }
        return slots[n]
    }

    private static func inline(_ line: String, slots: [String]) -> String {
        var text = escape(line)
        text = replace(text, pattern: "`([^`]+)`") { "<code>\($0[1])</code>" }
        text = replace(text, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\($0[1])</strong>" }
        text = replace(text, pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)") { "<em>\($0[1])</em>" }
        for (index, slot) in slots.enumerated() {
            let token = escape("\u{E000}\(index)\u{E001}")
            text = text.replacingOccurrences(of: token, with: slot)
        }
        return text
    }

    private static func replace(_ text: String, pattern: String, _ map: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let range = match.range(at: i)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            out += map(groups)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            out += ns.substring(from: cursor)
        }
        return out
    }

    private static func find(_ chars: [Character], from start: Int, marker: [Character]) -> Int? {
        var i = start
        while i + marker.count <= chars.count {
            if Array(chars[i..<(i + marker.count)]) == marker { return i }
            i += 1
        }
        return nil
    }

    private static func takeCommand(_ chars: [Character], from start: Int) -> Int? {
        guard start + 1 < chars.count, chars[start] == "\\", chars[start + 1].isLetter else { return nil }
        var j = start + 1
        while j < chars.count, chars[j].isLetter { j += 1 }
        var progressed = true
        while progressed {
            progressed = false
            let saved = j
            while j < chars.count, chars[j] == " " { j += 1 }
            if j < chars.count, chars[j] == "^" || chars[j] == "_" {
                j += 1
                progressed = true
            }
            if j < chars.count, chars[j] == "{" {
                var depth = 0
                while j < chars.count {
                    if chars[j] == "{" { depth += 1 }
                    else if chars[j] == "}" {
                        depth -= 1
                        j += 1
                        if depth == 0 { break }
                        continue
                    }
                    j += 1
                }
                progressed = true
            } else if !progressed {
                j = saved
            }
        }
        return j
    }

    private static func findInlineDollar(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "\n" { return nil }
            if chars[i] == "$", chars[i - 1] != " ", chars[i - 1] != "\\" { return i }
            i += 1
        }
        return nil
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
