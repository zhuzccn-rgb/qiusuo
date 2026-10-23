import XCTest
import LexiconCore

final class AppPathsTests: XCTestCase {
    func testDefaultInboxLivesUnderAirDropDownloads() {
        let inbox = AppPaths.defaultInboxURL
        XCTAssertEqual(inbox.lastPathComponent, "LexiconInbox")
        XCTAssertEqual(inbox.deletingLastPathComponent().path, AppPaths.airDropDirectory.path)
        XCTAssertFalse(inbox.path.lowercased().contains("onedrive"))
        XCTAssertFalse(inbox.path.lowercased().contains("cloudstorage"))
    }

    func testLegacyCloudInboxDetection() {
        XCTAssertTrue(AppPaths.isLegacyCloudInbox(
            "/Users/example/Library/CloudStorage/OneDrive-Example/LexiconInbox"
        ))
        XCTAssertTrue(AppPaths.isLegacyCloudInbox("/Users/x/OneDrive - Example/LexiconInbox"))
        XCTAssertFalse(AppPaths.isLegacyCloudInbox(AppPaths.defaultInboxURL.path))
        XCTAssertFalse(AppPaths.isLegacyCloudInbox("/tmp/LexiconInbox"))
    }
}
