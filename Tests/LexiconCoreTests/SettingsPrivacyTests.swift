import XCTest
import LexiconCore

final class SettingsPrivacyTests: XCTestCase {
    func testTokensAreNotPersistedAndLegacyTokenIsNotLoaded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try Database(fileURL: folder.appendingPathComponent("test.sqlite"))
        let store = ArchiveStore(database: db)
        try db.execute("INSERT INTO settings(key, value) VALUES('llm_api_key', 'synthetic-old-token')")
        XCTAssertEqual(try store.loadSettings().llmAPIKey, "")
        var settings = AppSettings()
        settings.llmAPIKey = "synthetic-session-token"
        try store.saveSettings(settings)
        XCTAssertTrue(try db.query("SELECT * FROM settings WHERE key='llm_api_key'").isEmpty)
        XCTAssertEqual(try store.loadSettings().llmAPIKey, "")
        XCTAssertEqual(settings.llmAPIKey, "synthetic-session-token")
    }
}
