import XCTest
import LexiconCalendar
import LexiconCore

final class CalendarMatcherTests: XCTestCase {
    func testInferredSubjects() {
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "高等数学"), SubjectPreset.math.rawValue)
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "MATH 1A"), SubjectPreset.math.rawValue)
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "Physics 7A"), SubjectPreset.physics.rawValue)
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "CHEM 1A"), SubjectPreset.chemistry.rawValue)
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "English R1B"), SubjectPreset.english.rawValue)
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "CS61A Lecture"), SubjectPreset.coding.rawValue)
        XCTAssertEqual(CalendarMatcher.inferredSubject(from: "计算机导论"), SubjectPreset.coding.rawValue)
        XCTAssertNil(CalendarMatcher.inferredSubject(from: "COLWRIT R1A Seminar"))
    }

    func testOverlapDuration() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let hour: TimeInterval = 3600
        XCTAssertEqual(
            CalendarMatcher.overlapDuration(
                aStart: noon,
                aEnd: noon.addingTimeInterval(hour),
                bStart: noon.addingTimeInterval(0.5 * hour),
                bEnd: noon.addingTimeInterval(2 * hour)
            ),
            0.5 * hour,
            accuracy: 0.01
        )
        XCTAssertLessThan(
            CalendarMatcher.overlapDuration(
                aStart: noon,
                aEnd: noon.addingTimeInterval(hour),
                bStart: noon.addingTimeInterval(2 * hour),
                bEnd: noon.addingTimeInterval(3 * hour)
            ),
            0
        )
    }

    func testMatchWindowUsesNinetyMinutesWhenDurationIsTiny() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let tiny = CalendarMatcher.recordingSpan(start: noon, duration: 0)
        XCTAssertEqual(tiny.end.timeIntervalSince(tiny.start), 90 * 60)
        let long = CalendarMatcher.recordingSpan(start: noon, duration: 3 * 3600)
        XCTAssertEqual(long.end.timeIntervalSince(long.start), 3 * 3600)
    }

    func testMatchesEventAllowsTenMinuteStartOrEndSlack() {
        let classStart = Date(timeIntervalSince1970: 1_700_000_000)
        let classEnd = classStart.addingTimeInterval(50 * 60)

        // Started 8 minutes early, stopped before class — still a hit.
        XCTAssertTrue(CalendarMatcher.matchesEvent(
            recStart: classStart.addingTimeInterval(-8 * 60),
            recEnd: classStart.addingTimeInterval(-6 * 60),
            eventStart: classStart,
            eventEnd: classEnd
        ))
        // Started 8 minutes late, only a short clip inside the class.
        XCTAssertTrue(CalendarMatcher.matchesEvent(
            recStart: classStart.addingTimeInterval(8 * 60),
            recEnd: classStart.addingTimeInterval(10 * 60),
            eventStart: classStart,
            eventEnd: classEnd
        ))
        // Stopped 5 minutes after class ended, started after it ended.
        XCTAssertTrue(CalendarMatcher.matchesEvent(
            recStart: classEnd.addingTimeInterval(1 * 60),
            recEnd: classEnd.addingTimeInterval(5 * 60),
            eventStart: classStart,
            eventEnd: classEnd
        ))
        // 12 minutes early and no overlap — too far.
        XCTAssertFalse(CalendarMatcher.matchesEvent(
            recStart: classStart.addingTimeInterval(-12 * 60),
            recEnd: classStart.addingTimeInterval(-11 * 60),
            eventStart: classStart,
            eventEnd: classEnd
        ))
    }

    func testVoiceMemoSavedAfterClassStillHitsThreePMLecture() {
        // Dwinelle Hall.m4a: Finder birth 16:32, duration 48:10, MATH 52 is 15:00–15:59.
        let saved = Date(timeIntervalSince1970: 1_788_148_364)
        let duration: TimeInterval = 48 * 60 + 10
        let recStart = saved.addingTimeInterval(-duration)
        let recEnd = saved
        let classStart = saved.addingTimeInterval(-92 * 60) // ~15:00
        let classEnd = classStart.addingTimeInterval(59 * 60)
        XCTAssertTrue(CalendarMatcher.matchesEvent(
            recStart: recStart,
            recEnd: recEnd,
            eventStart: classStart,
            eventEnd: classEnd
        ))
        XCTAssertFalse(CalendarMatcher.matchesEvent(
            recStart: saved,
            recEnd: saved.addingTimeInterval(duration),
            eventStart: classStart,
            eventEnd: classEnd
        ))
        XCTAssertGreaterThan(
            CalendarMatcher.placeBoost(placeHint: "Dwinelle Hall", title: "MATH 52 Lecture", location: "Dwinelle Hall 155"),
            0
        )
    }

    func testMatchScorePrefersLargerOverlap() {
        let classStart = Date(timeIntervalSince1970: 1_700_000_000)
        let classEnd = classStart.addingTimeInterval(50 * 60)
        let full = CalendarMatcher.matchScore(
            recStart: classStart,
            recEnd: classEnd,
            eventStart: classStart,
            eventEnd: classEnd
        )
        let late = CalendarMatcher.matchScore(
            recStart: classStart.addingTimeInterval(8 * 60),
            recEnd: classStart.addingTimeInterval(10 * 60),
            eventStart: classStart,
            eventEnd: classEnd
        )
        XCTAssertGreaterThan(full, late)
    }

    func testLateSavedVoiceMemoDoesNotStealNextClass() {
        let saved = Date(timeIntervalSince1970: 1_788_148_364)
        let duration: TimeInterval = 48 * 60 + 10
        let spans = [
            RecordingSpan(start: saved.addingTimeInterval(-duration), end: saved, anchor: .creationAsEnd),
            RecordingSpan(start: saved, end: saved.addingTimeInterval(duration), anchor: .creationAsStart)
        ]
        let mathStart = saved.addingTimeInterval(-92 * 60)
        let mathEnd = mathStart.addingTimeInterval(59 * 60)
        let laterStart = saved.addingTimeInterval(28 * 60)
        let laterEnd = laterStart.addingTimeInterval(60 * 60)
        let picked = CalendarMatcher.pickBest(
            intervals: spans,
            events: [
                CalendarEventSnapshot(
                    id: "math",
                    title: "MATH 52 Lecture",
                    location: "Dwinelle Hall 155",
                    start: mathStart,
                    end: mathEnd
                ),
                CalendarEventSnapshot(
                    id: "later",
                    title: "Evening Seminar",
                    location: "",
                    start: laterStart,
                    end: laterEnd
                )
            ]
        )
        XCTAssertEqual(picked?.event.id, "math")
    }

    func testCreationAtClassStartPrefersThatClassOverPreviousOverlap() {
        let start = Date(timeIntervalSince1970: 1_700_003_600)
        let duration: TimeInterval = 50 * 60
        let spans = [
            RecordingSpan(start: start.addingTimeInterval(-duration), end: start, anchor: .creationAsEnd),
            RecordingSpan(start: start, end: start.addingTimeInterval(duration), anchor: .creationAsStart)
        ]
        let previous = CalendarEventSnapshot(
            id: "previous",
            title: "MATH 52",
            location: "",
            start: start.addingTimeInterval(-60 * 60),
            end: start.addingTimeInterval(-10 * 60)
        )
        let current = CalendarEventSnapshot(
            id: "current",
            title: "CS 61A",
            location: "",
            start: start,
            end: start.addingTimeInterval(50 * 60)
        )
        let picked = CalendarMatcher.pickBest(intervals: spans, events: [previous, current])
        XCTAssertEqual(picked?.event.id, "current")
    }

    func testFilenameStampBeatsALaterClass() {
        let recStart = Date(timeIntervalSince1970: 1_700_000_000)
        let duration: TimeInterval = 50 * 60
        let spans = [
            RecordingSpan(start: recStart, end: recStart.addingTimeInterval(duration), anchor: .filenameStart)
        ]
        let lecture = CalendarEventSnapshot(
            id: "lecture",
            title: "MATH 52",
            location: "",
            start: recStart,
            end: recStart.addingTimeInterval(50 * 60)
        )
        let later = CalendarEventSnapshot(
            id: "later",
            title: "Office Hours",
            location: "",
            start: recStart.addingTimeInterval(60 * 60),
            end: recStart.addingTimeInterval(120 * 60)
        )
        let picked = CalendarMatcher.pickBest(intervals: spans, events: [lecture, later])
        XCTAssertEqual(picked?.event.id, "lecture")
    }

    func testAirDroppedVoiceMemoMediaStartHitsAfternoonClass() {
        // New Recording.m4a: mvhd 15:17 PDT, duration 41:49; Finder AirDrop 17:02.
        let mediaStart = Date(timeIntervalSince1970: 1_789_597_021) // 2026-09-16 22:17:01Z
        let duration: TimeInterval = 41 * 60 + 49
        let spans = [
            RecordingSpan(start: mediaStart, end: mediaStart.addingTimeInterval(duration), anchor: .mediaStart),
            RecordingSpan(
                start: mediaStart.addingTimeInterval(-duration),
                end: mediaStart,
                anchor: .creationAsEnd
            )
        ]
        let mathStart = mediaStart.addingTimeInterval(-17 * 60)
        let mathEnd = mathStart.addingTimeInterval(59 * 60)
        let laterStart = mediaStart.addingTimeInterval(105 * 60)
        let laterEnd = laterStart.addingTimeInterval(60 * 60)
        let picked = CalendarMatcher.pickBest(
            intervals: spans,
            events: [
                CalendarEventSnapshot(id: "math", title: "MATH 52 Lecture", location: "", start: mathStart, end: mathEnd),
                CalendarEventSnapshot(id: "later", title: "Evening Seminar", location: "", start: laterStart, end: laterEnd)
            ]
        )
        XCTAssertEqual(picked?.event.id, "math")
    }
}
