import XCTest
import LexiconCore

final class SummaryHTMLTests: XCTestCase {
    func testPlainTextIsNotMath() {
        XCTAssertFalse(SummaryHTML.containsMath("chain rule"))
        XCTAssertFalse(SummaryHTML.containsMath("costs $5 today"))
    }

    func testInlineAndDisplayAreDetected() {
        XCTAssertTrue(SummaryHTML.containsMath("the derivative is $x^2$"))
        XCTAssertTrue(SummaryHTML.containsMath("the derivative is \\frac{1}{2}"))
    }

    func testDisplayMathIsEscapedAndNotWrappedAsAParagraph() {
        let html = SummaryHTML.document(markdown: "\\[a < b\\]")
        XCTAssertTrue(html.contains("<div class=\"display\">\\[a &lt; b\\]</div>"))
        XCTAssertFalse(html.contains("<p>"))
    }

    func testTextBeforeAFormulaStays() {
        let html = SummaryHTML.document(markdown: "See $x^2$ next.")
        XCTAssertTrue(html.contains("See "))
        XCTAssertTrue(html.contains("\\(x^2\\)"))
        XCTAssertTrue(html.contains(" next."))
    }

    func testFencedCodeIsPreformattedAndEscaped() {
        let html = SummaryHTML.document(markdown: "```python\nx < y\n```")
        XCTAssertTrue(html.contains("<pre>"))
        XCTAssertTrue(html.contains("python"))
        XCTAssertTrue(html.contains("<code>x &lt; y</code>"))
        XCTAssertFalse(html.contains("<p>x"))
    }

    func testMathInsideAFenceDoesNotForceMathMode() {
        XCTAssertFalse(SummaryHTML.containsMath("```\n\\frac{1}{2}\n```"))
        XCTAssertFalse(SummaryHTML.containsMath("`\\frac{1}{2}`"))
        XCTAssertTrue(SummaryHTML.containsMath("```\n\\frac{1}{2}\n```\n\nThen \\frac{1}{2}."))
    }

    func testPlainTextWithoutMarkersSkipsTheMathWalk() {
        XCTAssertFalse(SummaryHTML.containsMath(String(repeating: "lecture ", count: 2_000)))
    }
}

final class MarkdownSourceTests: XCTestCase {
    func testFenceKeepsIndentAndDoesNotSwallowTheNextHeading() {
        let source = """
        ## Adding constraints

        ```python
        def cp(n):
            return n
        ```

        ## Pitfalls

        - `in` checks keys
        """
        let blocks = MarkdownSource.blocks(in: source)
        XCTAssertTrue(blocks.contains(.heading(2, "Adding constraints")))
        XCTAssertTrue(blocks.contains(.code(language: "python", text: "def cp(n):\n    return n")))
        XCTAssertTrue(blocks.contains(.heading(2, "Pitfalls")))
        XCTAssertTrue(blocks.contains(.bullet("`in` checks keys")))
    }

    func testUnclosedFenceKeepsLaterLinesAsCode() {
        XCTAssertEqual(
            MarkdownSource.blocks(in: "```\nalpha\n# not a heading"),
            [.code(language: "", text: "alpha\n# not a heading")]
        )
    }

    func testBlankLinesInsideCodeStay() {
        XCTAssertEqual(
            MarkdownSource.blocks(in: "```\na\n\nb\n```"),
            [.code(language: "", text: "a\n\nb")]
        )
    }

    func testProseStillCollapsesBlankLines() {
        XCTAssertEqual(
            MarkdownSource.blocks(in: "a\n\n\nb"),
            [.paragraph("a"), .blank, .paragraph("b")]
        )
    }
}
