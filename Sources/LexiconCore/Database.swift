import Foundation
import SQLite3

public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let fileURL: URL
    private var isRecovering = false

    public init(fileURL: URL = AppPaths.databaseFile) throws {
        self.fileURL = fileURL
        try openConnection()
        try migrate()
        try healIfNeeded()
    }

    deinit {
        lock.lock()
        checkpointLocked(mode: SQLITE_CHECKPOINT_TRUNCATE)
        sqlite3_close_v2(handle)
        handle = nil
        lock.unlock()
    }

    public func execute(_ sql: String, bindings: [DBValue] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            try executeLocked(sql, bindings: bindings)
        } catch {
            if !isRecovering, Self.isCorrupt(error) {
                try healLocked()
                try executeLocked(sql, bindings: bindings)
                return
            }
            throw error
        }
    }

    public func query(_ sql: String, bindings: [DBValue] = []) throws -> [[String: DBValue]] {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try queryLocked(sql, bindings: bindings)
        } catch {
            if !isRecovering, Self.isCorrupt(error) {
                try healLocked()
                return try queryLocked(sql, bindings: bindings)
            }
            throw error
        }
    }

    public func scalar(_ sql: String, bindings: [DBValue] = []) throws -> DBValue? {
        try query(sql, bindings: bindings).first?.values.first
    }

    public func checkpoint() {
        lock.lock()
        defer { lock.unlock() }
        checkpointLocked(mode: SQLITE_CHECKPOINT_PASSIVE)
    }

    public func rebuildLectureFTS() throws {
        lock.lock()
        defer { lock.unlock() }
        try rebuildLectureFTSLocked()
    }

    public static func isCorrupt(_ error: Error) -> Bool {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lower = text.lowercased()
        return lower.contains("malformed")
            || lower.contains("corrupt")
            || lower.contains("not a database")
    }

    private func openConnection() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(fileURL.path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            throw DBError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        try executeLocked("PRAGMA journal_mode=WAL")
        try executeLocked("PRAGMA synchronous=NORMAL")
        try executeLocked("PRAGMA temp_store=MEMORY")
        try executeLocked("PRAGMA cache_size=-8192")
        try executeLocked("PRAGMA foreign_keys=ON")
        try executeLocked("PRAGMA busy_timeout=8000")
        try executeLocked("PRAGMA wal_autocheckpoint=64")
        sqlite3_busy_timeout(handle, 8000)
    }

    private func migrate() throws {
        try executeLocked("""
            CREATE TABLE IF NOT EXISTS homework (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                subject TEXT NOT NULL DEFAULT '未分类',
                file_path TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'inbox',
                created_at REAL NOT NULL
            )
            """)
        try executeLocked("""
            CREATE TABLE IF NOT EXISTS mistakes (
                id TEXT PRIMARY KEY,
                homework_id TEXT NOT NULL DEFAULT '',
                subject TEXT NOT NULL DEFAULT '未分类',
                question TEXT NOT NULL,
                wrong_answer TEXT NOT NULL DEFAULT '',
                correct_answer TEXT NOT NULL DEFAULT '',
                analysis TEXT NOT NULL DEFAULT '',
                tags TEXT NOT NULL DEFAULT '',
                image_path TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL
            )
            """)
        try executeLocked("""
            CREATE TABLE IF NOT EXISTS lectures (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                subject TEXT NOT NULL DEFAULT '未分类',
                file_path TEXT NOT NULL DEFAULT '',
                transcript TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '',
                duration REAL NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            )
            """)
        try executeLocked("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
        try executeLocked("CREATE INDEX IF NOT EXISTS idx_homework_created ON homework(created_at DESC)")
        try executeLocked("CREATE INDEX IF NOT EXISTS idx_mistakes_created ON mistakes(created_at DESC)")
        try executeLocked("CREATE INDEX IF NOT EXISTS idx_lectures_created ON lectures(created_at DESC)")
        try addColumn("lectures", "tags", "TEXT NOT NULL DEFAULT ''")
        try addColumn("lectures", "calendar_event_id", "TEXT NOT NULL DEFAULT ''")
        do {
            try installLectureFTS()
        } catch {
            // Search falls back to in-memory matching.
        }
    }

    public func hasTable(_ name: String) -> Bool {
        let rows = (try? query(
            "SELECT name FROM sqlite_master WHERE name=? LIMIT 1",
            bindings: [.text(name)]
        )) ?? []
        return !rows.isEmpty
    }

    public var hasLectureFTS: Bool { hasTable("lectures_fts") }

    public func backfillLectureFTS() {
        guard hasLectureFTS else { return }
        do {
            let lectures = try scalar("SELECT count(*) FROM lectures")?.double ?? 0
            let indexed = try scalar("SELECT count(*) FROM lectures_fts")?.double ?? 0
            if indexed + 0.5 < lectures {
                try execute("INSERT INTO lectures_fts(lectures_fts) VALUES('rebuild')")
            }
        } catch {
            if Self.isCorrupt(error) {
                try? rebuildLectureFTS()
            }
        }
    }

    private func installLectureFTS() throws {
        do {
            try executeLocked(Self.lectureFTSSQL(tokenizer: "trigram"))
        } catch {
            try executeLocked(Self.lectureFTSSQL(tokenizer: "unicode61"))
        }
        try executeLocked("""
            CREATE TRIGGER IF NOT EXISTS lectures_fts_ai AFTER INSERT ON lectures BEGIN
                INSERT INTO lectures_fts(rowid, title, subject, tags, transcript, summary)
                VALUES (new.rowid, new.title, new.subject, new.tags, new.transcript, new.summary);
            END
            """)
        try executeLocked("""
            CREATE TRIGGER IF NOT EXISTS lectures_fts_ad AFTER DELETE ON lectures BEGIN
                INSERT INTO lectures_fts(lectures_fts, rowid, title, subject, tags, transcript, summary)
                VALUES ('delete', old.rowid, old.title, old.subject, old.tags, old.transcript, old.summary);
            END
            """)
        try executeLocked("""
            CREATE TRIGGER IF NOT EXISTS lectures_fts_au AFTER UPDATE ON lectures BEGIN
                INSERT INTO lectures_fts(lectures_fts, rowid, title, subject, tags, transcript, summary)
                VALUES ('delete', old.rowid, old.title, old.subject, old.tags, old.transcript, old.summary);
                INSERT INTO lectures_fts(rowid, title, subject, tags, transcript, summary)
                VALUES (new.rowid, new.title, new.subject, new.tags, new.transcript, new.summary);
            END
            """)
    }

    private static func lectureFTSSQL(tokenizer: String) -> String {
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS lectures_fts USING fts5(
            title,
            subject,
            tags,
            transcript,
            summary,
            content='lectures',
            content_rowid='rowid',
            tokenize='\(tokenizer)'
        )
        """
    }

    private func addColumn(_ table: String, _ name: String, _ definition: String) throws {
        try? executeLocked("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
    }

    private func healIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        // integrity_check can say ok while content-sync FTS5 still fails on UPDATE
        // (lecture 保存 fires the FTS trigger and surfaces "malformed").
        if integrityOKLocked(), ftsWriteOKLocked() {
            compactIfFragmentedLocked()
            return
        }
        try healLocked()
    }

    /// Content-sync FTS5 can look readable and still abort lecture upserts.
    private func ftsWriteOKLocked() -> Bool {
        do {
            let count = try scalarLocked("SELECT count(*) FROM lectures")?.double ?? 0
            guard count > 0 else { return true }
            try executeLocked("BEGIN IMMEDIATE")
            try executeLocked("UPDATE lectures SET title = title WHERE rowid = (SELECT MIN(rowid) FROM lectures)")
            try executeLocked("ROLLBACK")
            return true
        } catch {
            try? executeLocked("ROLLBACK")
            return false
        }
    }

    private func healLocked() throws {
        isRecovering = true
        defer { isRecovering = false }
        try? rebuildLectureFTSLocked()
        if integrityOKLocked() {
            checkpointLocked(mode: SQLITE_CHECKPOINT_TRUNCATE)
            return
        }
        try salvageLocked()
        if !integrityOKLocked() {
            throw DBError.executeFailed("database disk image is malformed")
        }
    }

    private func rebuildLectureFTSLocked() throws {
        try executeLocked("DROP TRIGGER IF EXISTS lectures_fts_ai")
        try executeLocked("DROP TRIGGER IF EXISTS lectures_fts_ad")
        try executeLocked("DROP TRIGGER IF EXISTS lectures_fts_au")
        try executeLocked("DROP TABLE IF EXISTS lectures_fts")
        try installLectureFTS()
        try executeLocked("INSERT INTO lectures_fts(lectures_fts) VALUES('rebuild')")
    }

    private func salvageLocked() throws {
        let homework = collectBestEffort("SELECT * FROM homework")
        let mistakes = collectBestEffort("SELECT * FROM mistakes")
        let lectures = collectBestEffort("SELECT * FROM lectures")
        let settings = collectBestEffort("SELECT * FROM settings")
        checkpointLocked(mode: SQLITE_CHECKPOINT_PASSIVE)
        sqlite3_close_v2(handle)
        handle = nil

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("archive.corrupt-\(stamp).sqlite")
        try? FileManager.default.copyItem(at: fileURL, to: backup)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileURL.path + "-shm"))

        do {
            try openConnection()
            try migrate()
            try insertSalvaged(
                "homework",
                rows: homework,
                columns: ["id", "title", "subject", "file_path", "notes", "status", "created_at"]
            )
            try insertSalvaged(
                "mistakes",
                rows: mistakes,
                columns: [
                    "id", "homework_id", "subject", "question", "wrong_answer", "correct_answer",
                    "analysis", "tags", "image_path", "created_at"
                ]
            )
            try insertSalvaged(
                "lectures",
                rows: lectures,
                columns: [
                    "id", "title", "subject", "file_path", "transcript", "summary",
                    "duration", "created_at", "tags", "calendar_event_id"
                ]
            )
            try insertSalvaged("settings", rows: settings, columns: ["key", "value"])
            checkpointLocked(mode: SQLITE_CHECKPOINT_TRUNCATE)
        } catch {
            sqlite3_close_v2(handle)
            handle = nil
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.copyItem(at: backup, to: fileURL)
            }
            throw error
        }
    }

    private func insertSalvaged(_ table: String, rows: [[String: DBValue]], columns: [String]) throws {
        guard !rows.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ",")
        let sql = "INSERT OR REPLACE INTO \(table) (\(columns.joined(separator: ","))) VALUES (\(placeholders))"
        for row in rows {
            try executeLocked(sql, bindings: columns.map { row[$0] ?? .null })
        }
    }

    private func collectBestEffort(_ sql: String) -> [[String: DBValue]] {
        do {
            return try queryLocked(sql)
        } catch {
            return []
        }
    }

    private func integrityOKLocked() -> Bool {
        do {
            let rows = try queryLocked("PRAGMA integrity_check")
            return rows.count == 1 && rows[0]["integrity_check"]?.string == "ok"
        } catch {
            return false
        }
    }

    private func compactIfFragmentedLocked() {
        let pages = (try? scalarLocked("PRAGMA page_count"))?.double ?? 0
        let free = (try? scalarLocked("PRAGMA freelist_count"))?.double ?? 0
        guard pages > 80, free > pages * 0.4 else { return }
        try? executeLocked("VACUUM")
        try? executeLocked("PRAGMA journal_mode=WAL")
        try? executeLocked("PRAGMA wal_autocheckpoint=64")
    }

    private func scalarLocked(_ sql: String) throws -> DBValue? {
        try queryLocked(sql).first?.values.first
    }

    private func checkpointLocked(mode: Int32) {
        guard handle != nil else { return }
        sqlite3_wal_checkpoint_v2(handle, nil, mode, nil, nil)
    }

    private func executeLocked(_ sql: String, bindings: [DBValue] = []) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, bindings)
        let step = sqlite3_step(stmt)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw DBError.executeFailed(errorMessage)
        }
    }

    private func queryLocked(_ sql: String, bindings: [DBValue] = []) throws -> [[String: DBValue]] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, bindings)
        var rows: [[String: DBValue]] = []
        rows.reserveCapacity(32)
        var step = sqlite3_step(stmt)
        while step == SQLITE_ROW {
            var row: [String: DBValue] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = column(stmt, index: i)
            }
            rows.append(row)
            step = sqlite3_step(stmt)
        }
        guard step == SQLITE_DONE else {
            throw DBError.executeFailed(errorMessage)
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(errorMessage)
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer?, _ values: [DBValue]) throws {
        for (index, value) in values.enumerated() {
            let i = Int32(index + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(stmt, i)
            case .text(let text):
                status = sqlite3_bind_text(stmt, i, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .double(let number):
                status = sqlite3_bind_double(stmt, i, number)
            case .int(let number):
                status = sqlite3_bind_int64(stmt, i, number)
            }
            guard status == SQLITE_OK else { throw DBError.bindFailed(errorMessage) }
        }
    }

    private func column(_ stmt: OpaquePointer?, index: Int32) -> DBValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            if let cString = sqlite3_column_text(stmt, index) {
                return .text(String(cString: cString))
            }
            return .text("")
        default:
            return .null
        }
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }
}

public enum DBValue: Sendable {
    case null
    case text(String)
    case double(Double)
    case int(Int64)

    public var string: String {
        switch self {
        case .text(let value): return value
        case .double(let value): return String(value)
        case .int(let value): return String(value)
        case .null: return ""
        }
    }

    public var double: Double {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .text(let value): return Double(value) ?? 0
        case .null: return 0
        }
    }
}

public enum DBError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let m), .prepareFailed(let m), .bindFailed(let m), .executeFailed(let m):
            return m
        }
    }
}
