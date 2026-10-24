import XCTest
@testable import LexiconCore

final class LocalizationTests: XCTestCase {
    func testSystemLanguagePriorityAndFallback() {
        XCTAssertEqual(L10n.language(for: ["en-US", "zh-Hans-CN"]), "en")
        XCTAssertEqual(L10n.language(for: ["zh-Hant-HK", "en-US"]), "zh-Hans")
        XCTAssertEqual(L10n.language(for: ["fr-FR", "en-GB"]), "en")
        XCTAssertEqual(L10n.language(for: ["fr-FR"]), "en")
    }

    func testBothResourceCatalogsAreLoaded() {
        XCTAssertEqual(L10n.text("求索", language: "en"), "Askfor")
        XCTAssertEqual(L10n.text("求索", language: "zh-Hans"), "求索")
        XCTAssertEqual(L10n.text("已获得授权，开始录音", language: "en"), "I have permission — start recording")
        XCTAssertEqual(L10n.lookup("自定义", language: "en"), "Custom")
    }

    func testInterpolationDoesNotTranslateOrInterpretUserData() {
        let filename = "我的笔记 %@ 100%.md"
        XCTAssertEqual(L10n.text("已导入 \(filename)", language: "en"), "Imported \(filename)")
        XCTAssertEqual(L10n.text("已导入 \(filename)", language: "zh-Hans"), "已导入 \(filename)")
        XCTAssertEqual(L10n.lookup("My custom course", language: "en"), "My custom course")
    }

    func testPersistentEnumIdentifiersStayStable() {
        XCTAssertEqual(SubjectPreset.math.rawValue, "数学")
        XCTAssertEqual(LLMPreset.custom.rawValue, "自定义")
    }
}
