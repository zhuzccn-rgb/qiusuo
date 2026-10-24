import XCTest
import LexiconLLM
import LexiconCore

final class LLMClientTests: XCTestCase {
    func testDecodeStringContent() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"  要点  "}}]}
        """.data(using: .utf8)!
        XCTAssertEqual(try LLMClient.decodeCompletion(json), "要点")
    }

    func testDecodeArrayContent() throws {
        let json = """
        {"choices":[{"message":{"content":[{"type":"text","text":"第一"},{"type":"text","text":"第二"}]}}]}
        """.data(using: .utf8)!
        XCTAssertEqual(try LLMClient.decodeCompletion(json), "第一第二")
    }

    func testDecodeLegacyTextChoice() throws {
        let json = """
        {"choices":[{"text":"plain"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(try LLMClient.decodeCompletion(json), "plain")
    }

    func testDecodeEmptyThrows() {
        let json = #"{"choices":[{"message":{"content":""}}]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try LLMClient.decodeCompletion(json))
    }

    func testDecodeModelIDsDedups() {
        let json = """
        {"data":[{"id":"gemma"},{"id":"gemma"},{"id":" qwen "},{"id":""}]}
        """.data(using: .utf8)!
        XCTAssertEqual(LLMClient.decodeModelIDs(json), ["gemma", "qwen"])
        XCTAssertEqual(LLMClient.decodeModelIDs(Data("nope".utf8)), [])
    }

    func testSSEKeepsTextAfterTheLastTool() throws {
        let body = """
        data: {"choices":[{"delta":{"content":"先读文件"}}]}

        event: hermes.tool.progress
        data: {"tool":"read_file","status":"completed"}

        data: {"choices":[{"delta":{"content":"## Key concepts\\nchain rule"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """
        XCTAssertEqual(try LLMClient.assembleSSE(body), "## Key concepts\nchain rule")
    }

    func testSSEErrorBeatsPartialText() {
        let body = """
        data: {"choices":[{"delta":{"content":"half"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"error"}],"hermes":{"error":"中断了"}}

        """
        XCTAssertThrowsError(try LLMClient.assembleSSE(body)) { error in
            XCTAssertTrue(String(describing: error).contains("中断了"))
        }
    }

    func testLecturePromptIncludesTranscriptText() {
        let transcript = "The chain rule applies to composite functions."
        let messages = LLMPrompts.summarizeLecture(
            title: "R1A",
            subject: "英语",
            recordedAt: "2026-09-03 14:09",
            durationText: "1:33:05",
            transcript: transcript
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[0].content.contains("untrusted"))
        XCTAssertTrue(messages[0].content.contains("English"))
        XCTAssertFalse(messages[0].content.contains(transcript))
        XCTAssertTrue(messages[1].content.contains("R1A"))
        XCTAssertTrue(messages[1].content.contains(transcript))
        XCTAssertFalse(messages[1].content.contains("qiusuo-lecture-notes"))
        XCTAssertFalse(messages[1].content.contains("search_files"))
    }

    func testMistakePromptIncludesFields() {
        let item = Mistake(subject: "数学", question: "极限", wrongAnswer: "0", correctAnswer: "1")
        let messages = LLMPrompts.summarizeMistake(item)
        XCTAssertTrue(messages[0].content.contains("不可信"))
        XCTAssertTrue(messages[1].content.contains("极限"))
        XCTAssertTrue(messages[1].content.contains("0"))
        XCTAssertTrue(messages[1].content.contains("1"))
    }

    func testOnDeviceTagPrefixAndParseStayShort() {
        _ = OnDeviceLectureTags.isAvailable
        XCTAssertEqual(OnDeviceLectureTags.maxPrefixChars, 1_800)
        let long = String(repeating: "a", count: 5_000)
        XCTAssertEqual(OnDeviceLectureTags.prefix(long).count, 1_800)
        XCTAssertEqual(OnDeviceLectureTags.parseTags("导数\n极值、链式法则"), "导数, 极值, 链式法则")
    }

    func testHTTPErrorMentionsToken() {
        let text = LLMClientError.http(401, "invalid_api_key").localizedDescription
        XCTAssertTrue(text.contains("Token") || text.contains("token") || text.contains("API"))
        XCTAssertEqual(LLMClientError.empty.localizedDescription, L10n.text("模型没有返回内容。"))
    }
}
