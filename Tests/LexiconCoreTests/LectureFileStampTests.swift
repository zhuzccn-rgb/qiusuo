import XCTest
import LexiconCore

final class LectureFileStampTests: XCTestCase {
    func testParsesRecorderFileName() {
        let date = LectureFileStamp.parse("20260902-151047")
        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 2)
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 10)
        XCTAssertEqual(parts.second, 47)
    }

    func testReadsStampFromFullPath() {
        let date = LectureFileStamp.recordedAt(
            filePath: "/tmp/recordings/20260902-151047.caf"
        )
        XCTAssertEqual(
            LectureFileStamp.parse("20260902-151047")?.timeIntervalSince1970,
            date?.timeIntervalSince1970
        )
        let guesses = LectureFileStamp.recordingGuesses(
            filePath: "/tmp/recordings/20260902-151047.caf",
            duration: 50 * 60,
            fallback: Date()
        )
        XCTAssertEqual(guesses.count, 1)
        XCTAssertEqual(guesses[0].anchor, .filenameStart)
    }

    func testIgnoresHumanTitles() {
        XCTAssertNil(LectureFileStamp.parse("Math 52"))
        XCTAssertNil(LectureFileStamp.parse("CS61 A Lecture 3"))
    }

    func testRecordedAtFallsBackToFileCreationDate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-birth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Dwinelle Hall.m4a")
        try Data([1]).write(to: file)
        let created = Date(timeIntervalSince1970: 1_788_000_000)
        LectureFileStamp.applyCreationDate(created, to: file.path)
        let read = LectureFileStamp.recordedAt(filePath: file.path)
        XCTAssertEqual(read?.timeIntervalSince1970 ?? 0, created.timeIntervalSince1970, accuracy: 1)
    }

    func testRecordingGuessesTreatsCreationAsEndWhenNameHasNoStamp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-guess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Dwinelle Hall.m4a")
        try Data([1]).write(to: file)
        let saved = Date(timeIntervalSince1970: 1_788_148_364) // 16:32-ish
        LectureFileStamp.applyCreationDate(saved, to: file.path)
        let duration: TimeInterval = 48 * 60 + 10
        let guesses = LectureFileStamp.recordingGuesses(filePath: file.path, duration: duration, fallback: saved)
        XCTAssertEqual(guesses.count, 2)
        XCTAssertEqual(guesses[0].anchor, .creationAsEnd)
        XCTAssertEqual(guesses[0].end.timeIntervalSince1970, saved.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(guesses[0].start.timeIntervalSince(saved), -duration, accuracy: 1)
        XCTAssertEqual(guesses[1].anchor, .creationAsStart)
        XCTAssertEqual(guesses[1].start.timeIntervalSince1970, saved.timeIntervalSince1970, accuracy: 1)
    }

    func testAirDropDelayUsesMpeg4MovieHeaderNotFinderBirth() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-m4a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("New Recording.m4a")
        let media = Date(timeIntervalSince1970: 1_789_597_021) // 2026-09-16 22:17:01Z
        try Data(Self.minimalM4A(creation: media)).write(to: file)
        let airdrop = media.addingTimeInterval(105 * 60)
        LectureFileStamp.applyCreationDate(airdrop, to: file.path)

        let parsed = LectureFileStamp.mediaCreationDate(at: file.path)
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, media.timeIntervalSince1970, accuracy: 1)

        let duration: TimeInterval = 41 * 60 + 49
        let guesses = LectureFileStamp.recordingGuesses(filePath: file.path, duration: duration, fallback: airdrop)
        XCTAssertEqual(guesses.count, 2)
        XCTAssertEqual(guesses[0].anchor, .mediaStart)
        XCTAssertEqual(guesses[0].start.timeIntervalSince1970, media.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(guesses[0].end.timeIntervalSince(media), duration, accuracy: 1)
        XCTAssertFalse(guesses.contains { abs($0.start.timeIntervalSince(airdrop)) < 1 })

        let recorded = LectureFileStamp.recordedAt(filePath: file.path)
        XCTAssertEqual(recorded?.timeIntervalSince1970 ?? 0, media.timeIntervalSince1970, accuracy: 1)
    }

    private static func minimalM4A(creation: Date) -> [UInt8] {
        func be32(_ value: UInt32) -> [UInt8] {
            [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        }
        let seconds = UInt32(creation.timeIntervalSince(LectureFileStamp.mpeg4Epoch))
        var mvhd: [UInt8] = []
        mvhd += be32(108)
        mvhd += Array("mvhd".utf8)
        mvhd += [0, 0, 0, 0]
        mvhd += be32(seconds)
        mvhd += be32(seconds)
        mvhd += be32(48_000)
        mvhd += be32(0)
        mvhd += be32(0x0001_0000)
        mvhd += [0x01, 0x00]
        mvhd += Array(repeating: 0, count: 10)
        mvhd += [
            0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x00, 0x00
        ]
        mvhd += Array(repeating: 0, count: 24)
        mvhd += be32(2)
        let moov: [UInt8] = be32(UInt32(8 + mvhd.count)) + Array("moov".utf8) + mvhd
        let ftyp: [UInt8] = be32(20) + Array("ftyp".utf8) + Array("M4A ".utf8) + be32(0) + Array("M4A ".utf8)
        return ftyp + moov
    }

    func testRecordedAtPrefersFilenameStampOverCreationDate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-stamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("20260902-151047.caf")
        try Data([1]).write(to: file)
        LectureFileStamp.applyCreationDate(Date(), to: file.path)
        let read = LectureFileStamp.recordedAt(filePath: file.path)
        XCTAssertEqual(
            read?.timeIntervalSince1970 ?? 0,
            LectureFileStamp.parse("20260902-151047")?.timeIntervalSince1970 ?? -1,
            accuracy: 0.5
        )
    }

    func testOrphansSkipKnownPathsAndNonAudio() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-orphan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let keep = folder.appendingPathComponent("20260903-120000.caf")
        let extra = folder.appendingPathComponent("20260903-130000.caf")
        let note = folder.appendingPathComponent("readme.txt")
        try Data([1, 2, 3]).write(to: keep)
        try Data([4, 5, 6]).write(to: extra)
        try Data([7]).write(to: note)
        let found = LectureOrphans.candidateURLs(in: folder, knownPaths: [keep.path])
        XCTAssertEqual(found.map(\.lastPathComponent), ["20260903-130000.caf"])
    }

    func testAudioImportKeepsInboxAndRecordingsInPlace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-import-\(UUID().uuidString)", isDirectory: true)
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox.appendingPathComponent("录音"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inboxClip = inbox.appendingPathComponent("录音/class.m4a")
        let localClip = recordings.appendingPathComponent("20260903-140948.caf")
        let outside = root.appendingPathComponent("Voice Memos.m4a")
        try Data([1]).write(to: inboxClip)
        try Data([1]).write(to: localClip)
        try Data([1]).write(to: outside)

        XCTAssertTrue(LectureAudioImport.isAudioFile(inboxClip))
        XCTAssertFalse(LectureAudioImport.isAudioFile(root.appendingPathComponent("notes.pdf")))
        XCTAssertTrue(LectureAudioImport.keepInPlace(source: inboxClip, inboxRoot: inbox, recordingsDirectory: recordings))
        XCTAssertTrue(LectureAudioImport.keepInPlace(source: localClip, inboxRoot: inbox, recordingsDirectory: recordings))
        XCTAssertFalse(LectureAudioImport.keepInPlace(source: outside, inboxRoot: inbox, recordingsDirectory: recordings))
    }

    func testAudioImportUniqueDestinationSkipsExisting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-dest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("memo.m4a")
        try Data([1]).write(to: first)
        let dest = LectureAudioImport.uniqueDestination(
            for: URL(fileURLWithPath: "/tmp/memo.m4a"),
            in: folder
        )
        XCTAssertEqual(dest.lastPathComponent, "memo-1.m4a")
    }
}
