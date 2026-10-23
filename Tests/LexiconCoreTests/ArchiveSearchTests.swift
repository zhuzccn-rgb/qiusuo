import XCTest
import LexiconCore

final class ArchiveSearchTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(ArchiveSearch.matches("", ["CS61A"]))
        XCTAssertTrue(ArchiveSearch.matches("   ", ["anything"]))
        XCTAssertEqual(ArchiveSearch.apply(["a", "b"], query: "  ") { $0 == "nope" }, ["a", "b"])
    }

    func testLocalizedStandardMatchingIsCaseInsensitive() {
        XCTAssertTrue(ArchiveSearch.matches("cs61a", ["CS61A Lecture"]))
        XCTAssertTrue(ArchiveSearch.matches("R1A", ["colwrit r1a seminar"]))
    }

    func testHomeworkSearchCoversTitleSubjectNotesAndFilename() {
        let item = Homework(
            title: "PSet 3",
            subject: "编程",
            filePath: "/tmp/recursion.pdf",
            notes: "tail call"
        )
        XCTAssertTrue(item.matchesSearch("pset"))
        XCTAssertTrue(item.matchesSearch("编程"))
        XCTAssertTrue(item.matchesSearch("tail"))
        XCTAssertTrue(item.matchesSearch("recursion"))
        XCTAssertFalse(item.matchesSearch("chemistry"))
    }

    func testMistakeSearchCoversQuestionTagsAndAnswers() {
        let item = Mistake(
            subject: "数学",
            question: "求极值",
            wrongAnswer: "x=0",
            correctAnswer: "x=2",
            analysis: "二阶导",
            tags: "导数, 极值"
        )
        XCTAssertTrue(item.matchesSearch("数学"))
        XCTAssertTrue(item.matchesSearch("极值"))
        XCTAssertTrue(item.matchesSearch("二阶"))
        XCTAssertTrue(item.matchesSearch("导数"))
        XCTAssertFalse(item.matchesSearch("CS61"))
    }

    func testLectureSearchCoversTranscriptAndTags() {
        let item = Lecture(
            title: "COLWRIT R1A Seminar",
            subject: "英语",
            transcript: "thesis statement",
            summary: "## 论点",
            tags: "writing, rhetoric"
        )
        XCTAssertTrue(item.matchesSearch("r1a"))
        XCTAssertTrue(item.matchesSearch("thesis"))
        XCTAssertTrue(item.matchesSearch("writing"))
        XCTAssertTrue(item.matchesSearch("论点"))
        XCTAssertFalse(item.matchesSearch("physics"))
    }

    func testSuggestionsDedupAndLimit() {
        let values = ["数学", "数学", "物理", "化学", "英语", "语文", "编程", "未分类", "额外"]
        XCTAssertEqual(
            ArchiveSearch.suggestions(from: values, query: "", limit: 8),
            ["数学", "物理", "化学", "英语", "语文", "编程", "未分类", "额外"]
        )
        XCTAssertEqual(ArchiveSearch.suggestions(from: values, query: "数"), ["数学"])
    }

    func testFTSMatchQueryEscapesAndJoinsTokens() {
        XCTAssertNil(ArchiveSearch.ftsMatchQuery("   "))
        XCTAssertEqual(ArchiveSearch.ftsMatchQuery("rarewordxyz"), "rarewordxyz")
        XCTAssertEqual(ArchiveSearch.ftsMatchQuery("thesis statement"), "\"thesis\" AND \"statement\"")
        XCTAssertEqual(ArchiveSearch.ftsMatchQuery("foo*bar"), "\"foo\" AND \"bar\"")
    }

    func testApplyLecturesUsesFTSHitsThenFallsBack() {
        let a = Lecture(id: "a", title: "First", transcript: "rarewordxyz")
        let b = Lecture(id: "b", title: "Second", transcript: "other")
        XCTAssertEqual(ArchiveSearch.applyLectures([a, b], query: "", ftsIDs: ["nope"]).map(\.id), ["a", "b"])
        XCTAssertEqual(ArchiveSearch.applyLectures([a, b], query: "rare", ftsIDs: ["a"]).map(\.id), ["a"])
        XCTAssertTrue(ArchiveSearch.applyLectures([a, b], query: "rare", ftsIDs: []).isEmpty)
        XCTAssertEqual(ArchiveSearch.applyLectures([a, b], query: "rarewordxyz", ftsIDs: nil).map(\.id), ["a"])
    }

    func testBrowseFilterIsInclusiveAndGroupsByCourse() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
        }
        let mathEarly = Lecture(id: "a", title: "Math 52", createdAt: day(2026, 9, 1, 15))
        let mathLate = Lecture(id: "b", title: "math 52", createdAt: day(2026, 9, 3, 8))
        let cs = Lecture(id: "c", title: "CS 61A", createdAt: day(2026, 9, 2, 10))
        let before = Lecture(id: "d", title: "Math 52", createdAt: day(2026, 8, 31, 23))
        let all = [mathEarly, mathLate, cs, before]

        let ranged = ArchiveSearch.applyBrowseFilter(
            all,
            filter: LectureBrowseFilter(start: day(2026, 9, 1, 0), end: day(2026, 9, 2, 23)),
            calendar: calendar
        )
        XCTAssertEqual(ranged.map(\.id), ["a", "c"])

        let course = ArchiveSearch.applyBrowseFilter(
            all,
            filter: LectureBrowseFilter(course: "math 52"),
            calendar: calendar
        )
        XCTAssertEqual(course.map(\.id), ["a", "b", "d"])

        let swapped = ArchiveSearch.applyBrowseFilter(
            all,
            filter: LectureBrowseFilter(start: day(2026, 9, 3, 0), end: day(2026, 9, 1, 0), course: "Math 52"),
            calendar: calendar
        )
        XCTAssertEqual(swapped.map(\.id), ["a", "b"])

        XCTAssertFalse(LectureBrowseFilter().isActive)
        XCTAssertFalse(LectureBrowseFilter(course: "   ").isActive)
        XCTAssertEqual(
            LectureBrowseFilter.courseName(of: Lecture(title: "  ", subject: "物理")),
            "物理"
        )

        let groups = ArchiveSearch.groupByCourse([mathEarly, cs, mathLate])
        XCTAssertEqual(groups.map(\.course), ["Math 52", "CS 61A"])
        XCTAssertEqual(groups[0].lectures.map(\.id), ["a", "b"])
        XCTAssertEqual(ArchiveSearch.courseNames(in: all), ["CS 61A", "Math 52"])
    }

    func testSelectedItemFollowsID() {
        let a = Lecture(id: "a", title: "First")
        let b = Lecture(id: "b", title: "Second")
        XCTAssertEqual(ArchiveSearch.item([a, b], id: "b")?.title, "Second")
        XCTAssertEqual(ArchiveSearch.item([a, b], id: "a")?.title, "First")
        XCTAssertNil(ArchiveSearch.item([a, b], id: "missing"))
        XCTAssertNil(ArchiveSearch.item([a, b], id: nil as String?))
    }
}

final class LectureTagsTests: XCTestCase {
    func testListSplitsChineseAndEnglishSeparators() {
        XCTAssertEqual(LectureTags.list("a, b，c; d；e"), ["a", "b", "c", "d", "e"])
    }

    func testJoinedDedupsCaseInsensitivelyAndCapsAtEight() {
        let joined = LectureTags.joined(["Math", "math", "A", "B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(LectureTags.list(joined).count, 8)
        XCTAssertFalse(LectureTags.list(joined).contains("H"))
    }

    func testSplitSummaryPullsTrailingTagsLine() {
        let raw = "# 课\n\n内容\n\n标签：导数, 极值\n"
        let split = LectureTags.splitSummary(raw)
        XCTAssertEqual(split.tags, "导数, 极值")
        XCTAssertFalse(split.summary.contains("标签"))
        XCTAssertTrue(split.summary.contains("内容"))
    }

    func testSplitSummaryLeavesBodyWhenNoTagLine() {
        let raw = "只有正文"
        let split = LectureTags.splitSummary(raw)
        XCTAssertEqual(split.summary, raw)
        XCTAssertEqual(split.tags, "")
    }

    func testExtractFromMarkdownTakesHeadingsAndBold() {
        let md = "## 关键概念\n\n记住 **链式法则** 和 **导数**"
        let tags = LectureTags.extractFromMarkdown(md)
        XCTAssertTrue(tags.contains("链式法则"))
        XCTAssertTrue(tags.contains("导数"))
    }

    func testExtractSkipsEnglishStructuralHeadings() {
        let md = "## Key concepts\n\nRemember **chain rule**"
        let tags = LectureTags.extractFromMarkdown(md)
        XCTAssertTrue(tags.contains("chain rule"))
        XCTAssertFalse(tags.lowercased().contains("key concepts"))
    }

    func testSplitSummaryPullsEnglishTagsLine() {
        let raw = "# Lecture\n\nbody\n\nTags: chain rule, substitution\n"
        let split = LectureTags.splitSummary(raw)
        XCTAssertEqual(split.tags, "chain rule, substitution")
        XCTAssertTrue(split.summary.contains("body"))
    }

    func testMerge() {
        XCTAssertEqual(LectureTags.merge("导数", "导数, 极值"), "导数, 极值")
    }
}

final class AppSettingsTests: XCTestCase {
    func testRequestModelIsTheConfiguredName() {
        var settings = AppSettings(llmPreset: .hermes, llmBaseURL: "http://127.0.0.1:8642/v1/", llmModel: "google/gemma-4-12b")
        XCTAssertEqual(settings.requestModel, "google/gemma-4-12b")
        XCTAssertEqual(settings.llmChatURL?.absoluteString, "http://127.0.0.1:8642/v1/chat/completions")
        XCTAssertEqual(settings.llmModelsURL?.absoluteString, "http://127.0.0.1:8642/v1/models")
        settings.llmModel = "hermes-agent"
        XCTAssertEqual(settings.requestModel, "hermes-agent")
        settings.llmModel = "research-model-v1"
        XCTAssertEqual(settings.requestModel, settings.llmModel)
    }

    func testEmptyBaseURLIsInvalid() {
        let settings = AppSettings(llmBaseURL: "  ")
        XCTAssertNil(settings.llmRootURL)
        XCTAssertNil(settings.llmChatURL)
    }

    func testPresetPorts() {
        XCTAssertEqual(LLMPreset.hermes.defaultPort, 8642)
        XCTAssertEqual(LLMPreset.lmStudio.defaultPort, 1234)
        XCTAssertEqual(LLMPreset.hermes.defaultModel, "hermes-agent")
    }
}

final class ArchiveStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testHomeworkMistakeLectureAndSettingsRoundTrip() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("archive.sqlite"))
        let store = ArchiveStore(database: db)

        var hw = Homework(title: "作业A", subject: "数学", filePath: "/tmp/a.pdf")
        try store.upsert(hw)
        hw.notes = "已改"
        try store.upsert(hw)
        XCTAssertEqual(try store.allHomework().first?.notes, "已改")
        XCTAssertEqual(try store.homework(withFilePath: "/tmp/a.pdf")?.title, "作业A")

        let mistake = Mistake(homeworkId: hw.id, subject: "数学", question: "1+1")
        try store.upsert(mistake)
        XCTAssertEqual(try store.allMistakes().count, 1)

        var lecture = Lecture(title: "R1A", filePath: "/tmp/r.caf", duration: 12)
        try store.upsert(lecture)
        lecture.transcript = "hello"
        lecture.tags = "writing"
        try store.upsert(lecture)
        XCTAssertEqual(try store.lecture(withFilePath: "/tmp/r.caf")?.transcript, "hello")
        XCTAssertEqual(try store.allLectures().first?.tags, "writing")

        var settings = AppSettings(inboxPath: "/tmp/inbox", llmPreset: .hermes, llmModel: "gemma")
        try store.saveSettings(settings)
        settings = try store.loadSettings()
        XCTAssertEqual(settings.inboxPath, "/tmp/inbox")
        XCTAssertEqual(settings.llmPreset, .hermes)
        XCTAssertEqual(settings.llmModel, "gemma")

        settings.voiceProcessing = true
        try store.saveSettings(settings)
        XCTAssertTrue(try store.loadSettings().voiceProcessing)

        try store.deleteHomework(id: hw.id)
        XCTAssertTrue(try store.allHomework().isEmpty)
        XCTAssertTrue(try store.allMistakes().isEmpty)

        try store.deleteLecture(id: lecture.id)
        XCTAssertTrue(try store.allLectures().isEmpty)
    }

    func testSchemaAddsLectureTagColumns() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("migrate.sqlite"))
        let columns = try db.query("PRAGMA table_info(lectures)").compactMap { $0["name"]?.string }
        XCTAssertTrue(columns.contains("tags"))
        XCTAssertTrue(columns.contains("calendar_event_id"))
    }

    func testFTSFindsRareWordAndLeavesLectureRowsAlone() throws {
        let db = try Database(fileURL: folder.appendingPathComponent("fts.sqlite"))
        let store = ArchiveStore(database: db)
        let lecture = Lecture(title: "R1A", transcript: "the rarewordxyz appears once")
        try store.upsert(lecture)
        store.backfillLectureFTS()
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM lectures")?.double, 1)
        if store.hasLectureFTS {
            XCTAssertEqual(store.searchLectureIDs(matching: "rarewordxyz"), [lecture.id])
        } else {
            XCTAssertNil(store.searchLectureIDs(matching: "rarewordxyz"))
        }
    }

    func testLegacyDatabaseWithoutFTSStillOpens() throws {
        let url = folder.appendingPathComponent("legacy.sqlite")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [url.path]
        let pipe = Pipe()
        proc.standardInput = pipe
        try proc.run()
        let sql = """
        CREATE TABLE lectures (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subject TEXT NOT NULL DEFAULT '',
            file_path TEXT NOT NULL DEFAULT '',
            transcript TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '',
            duration REAL NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        INSERT INTO lectures VALUES ('legacy','Old','英语','','rarewordxyz','',0,1);
        """
        pipe.fileHandleForWriting.write(Data(sql.utf8))
        pipe.fileHandleForWriting.closeFile()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        let db = try Database(fileURL: url)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM lectures")?.double, 1)
        let store = ArchiveStore(database: db)
        XCTAssertEqual(try store.allLectures().count, 1)
        XCTAssertEqual(try store.allLectures().first?.transcript, "rarewordxyz")
    }
}
