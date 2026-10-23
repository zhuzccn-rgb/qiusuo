import SwiftUI
import WebKit
import LexiconCore

struct MarkdownBlock: View {
    let source: String
    @State private var mathHeight: CGFloat = 44

    var body: some View {
        if SummaryHTML.containsMath(source) {
            MathSummaryWebView(html: SummaryHTML.document(markdown: source), height: $mathHeight)
                .id(source)
                .frame(height: max(44, mathHeight))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            markdownStack
        }
    }

    private var markdownStack: some View {
        let parsed = MarkdownSource.blocks(in: source)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsed.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownSource.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .foregroundStyle(.primary)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                inlineText(text)
            }
        case .paragraph(let text):
            inlineText(text)
                .font(.body)
        case .code(let language, let text):
            codeBlock(language: language, text: text)
        case .blank:
            Spacer().frame(height: 4)
        }
    }

    private func codeBlock(language: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    private func inlineText(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }
}

private struct MathSummaryWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "height")
        let webView = SummaryWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(html, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html, into: webView)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        @Binding var height: CGFloat
        private var loaded = ""

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func load(_ html: String, into webView: WKWebView) {
            guard html != loaded else { return }
            loaded = html
            webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            // Notes are a local display surface. Links never navigate or send content automatically.
            let isLocalDocument = url?.absoluteString == "about:blank"
                || (url?.isFileURL == true
                    && url?.standardizedFileURL.path == Bundle.main.resourceURL?.standardizedFileURL.path)
            if navigationAction.navigationType == .other, isLocalDocument {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let number = message.body as? NSNumber
            let value = number.map { CGFloat(truncating: $0) } ?? 44
            if abs(height - value) > 1 {
                height = value
            }
        }
    }
}

/// The formula page must not keep the scroll wheel. The lecture page behind it scrolls.
private final class SummaryWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        var view = superview
        while let current = view {
            if let scroll = current as? NSScrollView {
                scroll.scrollWheel(with: event)
                return
            }
            view = current.superview
        }
        super.scrollWheel(with: event)
    }
}
