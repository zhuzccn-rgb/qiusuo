import XCTest
import LexiconCore

final class LectureTranscriptLayoutTests: XCTestCase {
    func testEmptyAndShortStaySingleChunk() {
        XCTAssertTrue(LectureTranscriptLayout.chunks("").isEmpty)
        let short = String(repeating: "okay ", count: 80)
        XCTAssertEqual(LectureTranscriptLayout.chunks(short), [short])
    }

    func testLongRunSplitsNearTarget() {
        let text = String(repeating: "word ", count: 2_400)
        let parts = LectureTranscriptLayout.chunks(text)
        XCTAssertGreaterThan(parts.count, 4)
        XCTAssertLessThanOrEqual(parts.map(\.count).max() ?? 0, LectureTranscriptLayout.hardLimit)
        XCTAssertFalse(parts.contains { $0.isEmpty })
        XCTAssertEqual(parts.joined().filter { !$0.isWhitespace }, text.filter { !$0.isWhitespace })
    }

    func testPrefersSentenceBreaks() {
        let sentence = String(repeating: "clause ", count: 80) + "end. "
        let text = String(repeating: sentence, count: 30)
        let parts = LectureTranscriptLayout.chunks(text)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.dropLast().contains { $0.hasSuffix(".") || $0.hasSuffix(". ") })
    }

    func testClassroomSizedTranscriptChunksQuickly() {
        let text = String(repeating: "The derivative of cosine is negative sine. ", count: 1_400)
        XCTAssertGreaterThan(text.count, 50_000)
        var parts: [String] = []
        measure {
            parts = LectureTranscriptLayout.chunks(text)
        }
        XCTAssertGreaterThan(parts.count, 20)
        XCTAssertEqual(parts.joined().filter { !$0.isWhitespace }, text.filter { !$0.isWhitespace })
    }
}
