import XCTest
import LexiconCore

final class LLMEndpointTests: XCTestCase {
    func testLoopbackHTTPAndRemoteHTTPSAreAccepted() throws {
        let loopback = try XCTUnwrap(success("http://127.0.0.1:8080/v1"))
        XCTAssertEqual(loopback.host, "127.0.0.1")
        let localhost = try XCTUnwrap(success("HTTP://LOCALHOST:11434/v1/"))
        XCTAssertEqual(localhost.host?.lowercased(), "localhost")
        let v6 = try XCTUnwrap(success("http://[::1]:8642/v1"))
        XCTAssertEqual(v6.host?.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""), "::1")
        let remote = try XCTUnwrap(success("https://api.example.com/v1"))
        XCTAssertEqual(remote.scheme, "https")
        XCTAssertEqual(remote.host, "api.example.com")
        let secureLoopback = try XCTUnwrap(success("https://127.0.0.1:8080/v1"))
        XCTAssertEqual(secureLoopback.scheme, "https")
    }

    func testMalformedURLsAreRejected() {
        for raw in ["", "   ", "not a url", "http://", "://127.0.0.1", "ftp://127.0.0.1/v1", "file:///tmp/lecture.caf", "https://example.com/v1?token=secret", "https://example.com/v1#secret", "http://localhost:99999/v1", "https://example.com/a b"] {
            XCTAssertEqual(LLMEndpoint.rootURL(from: raw), .failure(.malformed), raw)
        }
    }

    func testEmbeddedCredentialsAreRejectedEvenOnLoopback() {
        for raw in [
            "http://user:pass@127.0.0.1:8080/v1",
            "http://user@localhost:8080/v1",
            "https://user:secret@api.example.com/v1",
            "http://user:pass@[::1]:8080/v1"
        ] {
            XCTAssertEqual(LLMEndpoint.rootURL(from: raw), .failure(.embeddedCredentials), raw)
        }
    }

    func testRemoteHTTPIsRejected() {
        for raw in [
            "http://192.0.2.10:1234/v1",
            "http://192.168.1.10:1234/v1",
            "http://api.example.com/v1",
            "http://127.0.0.2:8080/v1",
            "http://0.0.0.0:8080/v1"
        ] {
            XCTAssertEqual(LLMEndpoint.rootURL(from: raw), .failure(.insecureTransport), raw)
        }
    }

    func testChatURLUsesTheValidatedRoot() throws {
        let chat = try XCTUnwrap(chatSuccess("http://127.0.0.1:8642/v1/"))
        XCTAssertEqual(chat.absoluteString, "http://127.0.0.1:8642/v1/chat/completions")
        XCTAssertEqual(LLMEndpoint.chatURL(from: "http://192.0.2.10:1234/v1"), .failure(.insecureTransport))
        XCTAssertEqual(LLMEndpoint.modelsURL(from: "https://user:pw@example.com/v1"), .failure(.embeddedCredentials))
    }

    func testSettingsHideRejectedEndpoints() {
        let remote = AppSettings(llmBaseURL: "http://192.0.2.10:1234/v1")
        XCTAssertNil(remote.llmRootURL)
        XCTAssertNil(remote.llmChatURL)
        XCTAssertNil(remote.llmModelsURL)
        let creds = AppSettings(llmBaseURL: "https://user:secret@example.com/v1")
        XCTAssertNil(creds.llmChatURL)
        let blank = AppSettings(llmBaseURL: "  ")
        XCTAssertNil(blank.llmRootURL)
    }

    func testPresetDefaultsStayOnLoopback() throws {
        let defaults = AppSettings()
        XCTAssertEqual(defaults.llmBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(defaults.llmPreset, .llamaCpp)
        XCTAssertFalse(defaults.voiceProcessing)
        XCTAssertEqual(defaults.requestModel, defaults.llmModel)
        for preset in LLMPreset.allCases {
            XCTAssertEqual(preset.defaultBaseURL, "http://127.0.0.1:\(preset.defaultPort)/v1")
            XCTAssertFalse(preset.defaultBaseURL.contains("192.0.2.10"))
            let settings = AppSettings(
                llmPreset: preset,
                llmBaseURL: preset.defaultBaseURL,
                llmModel: preset.defaultModel ?? "local"
            )
            XCTAssertEqual(settings.llmChatURL?.host, "127.0.0.1")
            XCTAssertEqual(settings.requestModel, settings.llmModel)
            let root = try XCTUnwrap(success(preset.defaultBaseURL))
            XCTAssertEqual(root.scheme, "http")
        }
    }

    private func success(_ raw: String) -> URL? {
        if case .success(let url) = LLMEndpoint.rootURL(from: raw) { return url }
        return nil
    }

    private func chatSuccess(_ raw: String) -> URL? {
        if case .success(let url) = LLMEndpoint.chatURL(from: raw) { return url }
        return nil
    }
}
