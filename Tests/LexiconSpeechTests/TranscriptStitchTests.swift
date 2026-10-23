import XCTest
import LexiconSpeech

final class TranscriptStitchTests: XCTestCase {
    func testJoinsWordsIntoASentence() {
        var text = ""
        text = TranscriptStitch.append(text, "Hello")
        text = TranscriptStitch.append(text, "everyone,")
        text = TranscriptStitch.append(text, "let's get started.")
        XCTAssertEqual(text, "Hello everyone, let's get started.")
    }

    func testKeepsPunctuationStuckToPreviousWord() {
        let text = TranscriptStitch.append("today", ".")
        XCTAssertEqual(text, "today.")
    }

    func testParagraphBreak() {
        let next = TranscriptStitch.append(TranscriptStitch.paragraph("First sentence."), "Second sentence.")
        XCTAssertEqual(next, "First sentence.\nSecond sentence.")
    }

    func testParagraphGapIsNamedConstant() {
        XCTAssertEqual(TranscriptStitch.paragraphGap, 1.8, accuracy: 0.0001)
    }

    func testShouldBreakUsesGapAndIgnoresTinyPreviousEnd() {
        XCTAssertFalse(TranscriptStitch.shouldBreak(previousEnd: 10, start: 11.7))
        XCTAssertTrue(TranscriptStitch.shouldBreak(previousEnd: 10, start: 11.81))
        XCTAssertFalse(TranscriptStitch.shouldBreak(previousEnd: 0.1, start: 8))
        XCTAssertFalse(TranscriptStitch.shouldBreak(previousEnd: 4, start: .nan))
    }

    func testClockAndTimestampPrefix() {
        XCTAssertEqual(TranscriptStitch.clock(0), "0:00")
        XCTAssertEqual(TranscriptStitch.clock(724), "12:04")
        XCTAssertEqual(TranscriptStitch.clock(3725), "1:02:05")
        XCTAssertEqual(TranscriptStitch.timestampPrefix(724), "[12:04] ")
    }

    func testAppendSegmentStampsNewParagraphsOnly() {
        var text = TranscriptStitch.appendSegment(
            existing: "",
            incoming: "Hello class.",
            start: 0,
            previousEnd: 0
        )
        XCTAssertEqual(text, "[0:00] Hello class.")

        text = TranscriptStitch.appendSegment(
            existing: text,
            incoming: "Next idea.",
            start: 3.0,
            previousEnd: 2.0
        )
        XCTAssertEqual(text, "[0:00] Hello class. Next idea.")

        text = TranscriptStitch.appendSegment(
            existing: text,
            incoming: "After a pause.",
            start: 724,
            previousEnd: 3.5
        )
        XCTAssertEqual(text, "[0:00] Hello class. Next idea.\n[12:04] After a pause.")
    }
}
