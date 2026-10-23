import Foundation

public final class ArchiveStore: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    public convenience init() throws {
        try self.init(database: Database())
    }

    // MARK: Homework

    public func allHomework() throws -> [Homework] {
        try db.query("SELECT * FROM homework ORDER BY created_at DESC").map(Self.mapHomework)
    }

    public func upsert(_ item: Homework) throws {
        try db.execute(
            """
            INSERT INTO homework (id, title, subject, file_path, notes, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                subject=excluded.subject,
                file_path=excluded.file_path,
                notes=excluded.notes,
                status=excluded.status
            """,
            bindings: [
                .text(item.id), .text(item.title), .text(item.subject),
                .text(item.filePath), .text(item.notes), .text(item.status.rawValue),
                .double(item.createdAt.timeIntervalSince1970)
            ]
        )
    }

    public func deleteHomework(id: String) throws {
        try db.execute("DELETE FROM homework WHERE id=?", bindings: [.text(id)])
        try db.execute("DELETE FROM mistakes WHERE homework_id=?", bindings: [.text(id)])
    }

    public func homework(withFilePath path: String) throws -> Homework? {
        try db.query("SELECT * FROM homework WHERE file_path=? LIMIT 1", bindings: [.text(path)])
            .first
            .map(Self.mapHomework)
    }

    // MARK: Mistakes

    public func allMistakes() throws -> [Mistake] {
        try db.query("SELECT * FROM mistakes ORDER BY created_at DESC").map(Self.mapMistake)
    }

    public func upsert(_ item: Mistake) throws {
        try db.execute(
            """
            INSERT INTO mistakes (
                id, homework_id, subject, question, wrong_answer, correct_answer,
                analysis, tags, image_path, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                homework_id=excluded.homework_id,
                subject=excluded.subject,
                question=excluded.question,
                wrong_answer=excluded.wrong_answer,
                correct_answer=excluded.correct_answer,
                analysis=excluded.analysis,
                tags=excluded.tags,
                image_path=excluded.image_path
            """,
            bindings: [
                .text(item.id), .text(item.homeworkId), .text(item.subject),
                .text(item.question), .text(item.wrongAnswer), .text(item.correctAnswer),
                .text(item.analysis), .text(item.tags), .text(item.imagePath),
                .double(item.createdAt.timeIntervalSince1970)
            ]
        )
    }

    public func deleteMistake(id: String) throws {
        try db.execute("DELETE FROM mistakes WHERE id=?", bindings: [.text(id)])
    }

    public func mistake(withImagePath path: String) throws -> Mistake? {
        try db.query("SELECT * FROM mistakes WHERE image_path=? LIMIT 1", bindings: [.text(path)])
            .first
            .map(Self.mapMistake)
    }

    // MARK: Lectures

    public func allLectures() throws -> [Lecture] {
        try db.query("SELECT * FROM lectures ORDER BY created_at DESC").map(Self.mapLecture)
    }

    public func upsert(_ item: Lecture) throws {
        try db.execute(
            """
            INSERT INTO lectures (
                id, title, subject, file_path, transcript, summary, duration, created_at, tags, calendar_event_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                subject=excluded.subject,
                file_path=excluded.file_path,
                transcript=excluded.transcript,
                summary=excluded.summary,
                duration=excluded.duration,
                tags=excluded.tags,
                calendar_event_id=excluded.calendar_event_id
            """,
            bindings: [
                .text(item.id), .text(item.title), .text(item.subject), .text(item.filePath),
                .text(item.transcript), .text(item.summary), .double(item.duration),
                .double(item.createdAt.timeIntervalSince1970),
                .text(item.tags), .text(item.calendarEventId)
            ]
        )
    }

    public func deleteLecture(id: String) throws {
        try db.execute("DELETE FROM lectures WHERE id=?", bindings: [.text(id)])
    }

    public func lecture(withFilePath path: String) throws -> Lecture? {
        try db.query("SELECT * FROM lectures WHERE file_path=? LIMIT 1", bindings: [.text(path)])
            .first
            .map(Self.mapLecture)
    }

    public var hasLectureFTS: Bool { db.hasLectureFTS }

    public func backfillLectureFTS() {
        db.backfillLectureFTS()
    }

    public func checkpoint() {
        db.checkpoint()
    }

    /// Nil means FTS is missing or the query failed — caller should fall back.
    public func searchLectureIDs(matching raw: String) -> [String]? {
        guard let match = ArchiveSearch.ftsMatchQuery(raw) else { return [] }
        guard db.hasLectureFTS else { return nil }
        do {
            let rows = try db.query(
                """
                SELECT lectures.id AS id
                FROM lectures_fts
                JOIN lectures ON lectures.rowid = lectures_fts.rowid
                WHERE lectures_fts MATCH ?
                """,
                bindings: [.text(match)]
            )
            return rows.compactMap { $0["id"]?.string }
        } catch {
            return nil
        }
    }

    // MARK: Settings

    public func loadSettings() throws -> AppSettings {
        let rows = try db.query("SELECT key, value FROM settings")
        var map: [String: String] = [:]
        for row in rows {
            if let key = row["key"]?.string, let value = row["value"]?.string {
                map[key] = value
            }
        }
        var settings = AppSettings()
        if let path = map["inbox_path"], !path.isEmpty {
            settings.inboxPath = path
        } else {
            settings.inboxPath = AppPaths.defaultInboxURL.path
        }
        if let raw = map["llm_preset"], let preset = LLMPreset(rawValue: raw) {
            settings.llmPreset = preset
        }
        settings.llmBaseURL = map["llm_base_url"] ?? settings.llmBaseURL
        // Credentials are session-only; never restore a token from the archive.
        settings.llmAPIKey = ""
        settings.llmModel = map["llm_model"] ?? settings.llmModel
        settings.speechLocale = map["speech_locale"] ?? settings.speechLocale
        settings.calendarExcludedIds = map["calendar_excluded_ids"] ?? ""
        settings.voiceProcessing = map["voice_processing"] == "1"
        return settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        // Remove a legacy plaintext token if an existing archive is opened.
        // SQLite backups may still contain it; rotate old tokens if necessary.
        try db.execute("DELETE FROM settings WHERE key = 'llm_api_key'")
        let pairs: [(String, String)] = [
            ("inbox_path", settings.inboxPath),
            ("llm_preset", settings.llmPreset.rawValue),
            ("llm_base_url", settings.llmBaseURL),
            ("llm_model", settings.llmModel),
            ("speech_locale", settings.speechLocale),
            ("calendar_excluded_ids", settings.calendarExcludedIds),
            ("voice_processing", settings.voiceProcessing ? "1" : "0")
        ]
        for (key, value) in pairs {
            try db.execute(
                "INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                bindings: [.text(key), .text(value)]
            )
        }
    }

    // MARK: Mapping

    private static func mapHomework(_ row: [String: DBValue]) -> Homework {
        Homework(
            id: row["id"]?.string ?? UUID().uuidString,
            title: row["title"]?.string ?? "",
            subject: row["subject"]?.string ?? "未分类",
            filePath: row["file_path"]?.string ?? "",
            notes: row["notes"]?.string ?? "",
            status: HomeworkStatus(rawValue: row["status"]?.string ?? "") ?? .inbox,
            createdAt: Date(timeIntervalSince1970: row["created_at"]?.double ?? 0)
        )
    }

    private static func mapMistake(_ row: [String: DBValue]) -> Mistake {
        Mistake(
            id: row["id"]?.string ?? UUID().uuidString,
            homeworkId: row["homework_id"]?.string ?? "",
            subject: row["subject"]?.string ?? "未分类",
            question: row["question"]?.string ?? "",
            wrongAnswer: row["wrong_answer"]?.string ?? "",
            correctAnswer: row["correct_answer"]?.string ?? "",
            analysis: row["analysis"]?.string ?? "",
            tags: row["tags"]?.string ?? "",
            imagePath: row["image_path"]?.string ?? "",
            createdAt: Date(timeIntervalSince1970: row["created_at"]?.double ?? 0)
        )
    }

    private static func mapLecture(_ row: [String: DBValue]) -> Lecture {
        Lecture(
            id: row["id"]?.string ?? UUID().uuidString,
            title: row["title"]?.string ?? "",
            subject: row["subject"]?.string ?? "未分类",
            filePath: row["file_path"]?.string ?? "",
            transcript: row["transcript"]?.string ?? "",
            summary: row["summary"]?.string ?? "",
            duration: row["duration"]?.double ?? 0,
            createdAt: Date(timeIntervalSince1970: row["created_at"]?.double ?? 0),
            tags: row["tags"]?.string ?? "",
            calendarEventId: row["calendar_event_id"]?.string ?? ""
        )
    }
}
