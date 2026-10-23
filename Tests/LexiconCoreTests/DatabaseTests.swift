import XCTest
import LexiconCore

final class DatabaseTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testQueryThrowsOnBadSQL() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("bad-sql.sqlite"))
        XCTAssertThrowsError(try db.query("THIS IS NOT SQL"))
    }

    func testQueryThrowsWhenStepFails() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("step.sqlite"))
        XCTAssertThrowsError(try db.query("SELECT * FROM lectures_missing"))
    }

    func testCorruptMessageDetection() {
        XCTAssertTrue(Database.isCorrupt(DBError.executeFailed("database disk image is malformed")))
        XCTAssertTrue(Database.isCorrupt(DBError.executeFailed("database disk image is MALFORMED")))
        XCTAssertFalse(Database.isCorrupt(DBError.executeFailed("UNIQUE constraint failed")))
    }

    func testRepeatedLargeLectureUpsertsKeepIntegrityAndFTS() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("churn.sqlite"))
        let store = ArchiveStore(database: db)
        var lecture = Lecture(title: "COLWRIT R1A Seminar", subject: "英语", transcript: String(repeating: "okay ", count: 4000))
        for i in 0..<24 {
            lecture.transcript += " chunk-\(i) rarewordxyz"
            try store.upsert(lecture)
        }
        store.checkpoint()
        let check = try db.query("PRAGMA integrity_check")
        XCTAssertEqual(check.first?["integrity_check"]?.string, "ok")
        XCTAssertEqual(try store.allLectures().count, 1)
        if store.hasLectureFTS {
            XCTAssertEqual(store.searchLectureIDs(matching: "rarewordxyz"), [lecture.id])
        }
    }

    func testOpenProbeDoesNotChangeLectureRows() throws {
        let url = folder.appendingPathComponent("probe.sqlite")
        let db = try Database(fileURL: url)
        let store = ArchiveStore(database: db)
        let lecture = Lecture(title: "R1A", transcript: "hello")
        try store.upsert(lecture)
        let reopened = try Database(fileURL: url)
        XCTAssertEqual(try ArchiveStore(database: reopened).allLectures().first?.title, "R1A")
        try reopened.execute("UPDATE lectures SET title = title")
    }

    func testRebuildFTSRestoresSearch() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("rebuild.sqlite"))
        let store = ArchiveStore(database: db)
        let lecture = Lecture(title: "MATH 52", transcript: "substitution cosine rarewordxyz")
        try store.upsert(lecture)
        try db.rebuildLectureFTS()
        XCTAssertEqual(try db.query("PRAGMA integrity_check").first?["integrity_check"]?.string, "ok")
        if store.hasLectureFTS {
            XCTAssertEqual(store.searchLectureIDs(matching: "rarewordxyz"), [lecture.id])
        }
        XCTAssertEqual(try store.allLectures().first?.transcript, lecture.transcript)
    }
}
