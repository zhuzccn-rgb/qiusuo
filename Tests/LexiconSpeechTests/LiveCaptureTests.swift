import AVFoundation
import XCTest
import LexiconSpeech

/// Hits the real mic for a few seconds. Skips if the test runner has no microphone TCC.
final class LiveCaptureTests: XCTestCase {
    func testBuiltInPathWritesNonEmptyCAF() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["QIUSUO_LIVE_MIC_TESTS"] == "1",
            "Live microphone capture is opt-in: QIUSUO_LIVE_MIC_TESTS=1"
        )
        let rec = AudioRecorder()
        let allowed = await rec.requestPermission()
        try XCTSkipUnless(allowed, "测试进程没有麦克风权限，改由 dist/求索.app 验证")

        let url = try rec.start(voiceProcessing: false)
        defer {
            rec.unprime()
            try? FileManager.default.removeItem(at: url)
        }
        try await Task.sleep(nanoseconds: 2_800_000_000)
        let stopped = try rec.stop()
        rec.unprime()

        XCTAssertEqual(stopped?.path, url.path)
        XCTAssertGreaterThan(rec.framesWritten, 48_000)
        XCTAssertGreaterThan(rec.capturedSeconds, 1.5)
        XCTAssertFalse(AudioFileIO.looksEmpty(url))
        XCTAssertGreaterThan(PCMReader.duration(of: url), 1.5)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000, accuracy: 1)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertGreaterThan(rec.capturedPeak, 0.00005)
    }
}
