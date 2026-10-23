import AVFoundation
import XCTest
import LexiconCore
import LexiconSpeech

final class AudioFileIOTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testMissingAndTinyFilesLookEmpty() throws {
        let missing = folder.appendingPathComponent("gone.m4a")
        XCTAssertTrue(AudioFileIO.looksEmpty(missing))

        let tiny = folder.appendingPathComponent("header.m4a")
        try Data([0, 0, 0, 0x1C, 0x66, 0x74, 0x79, 0x70]).write(to: tiny)
        XCTAssertTrue(AudioFileIO.looksEmpty(tiny))
        XCTAssertEqual(AudioFileIO.fileSize(tiny), 8)
    }

    func testLargeFileWithoutDurationIsNotTreatedEmpty() throws {
        let bulky = folder.appendingPathComponent("unknown.bin")
        try Data(repeating: 1, count: 80_000).write(to: bulky)
        XCTAssertFalse(AudioFileIO.looksEmpty(bulky))
    }

    func testInvalidFileErrorCode() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: AudioFileIO.invalidFileCode)
        XCTAssertTrue(AudioFileIO.isInvalid(error))
        XCTAssertTrue(AudioFileIO.message(for: error).contains("空"))
        let other = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "nope"])
        XCTAssertEqual(AudioFileIO.message(for: other), "nope")
    }

    func testUtteranceSilenceSkipDoesNotRewriteFile() throws {
        let url = try writeSilence(seconds: 0.8)
        let before = try Data(contentsOf: url)
        let reader = try PCMReader(url: url)
        let skipped = try UtteranceSilenceSkip.skipLeading(reader: reader, from: 0)
        let energy = try reader.skipSilence(from: 0)
        XCTAssertEqual(skipped, energy, accuracy: 0.05)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testPCMRoundTripDurationAndSilenceSkip() throws {
        let url = try writeSilence(seconds: 1.2)
        XCTAssertFalse(AudioFileIO.looksEmpty(url))
        XCTAssertGreaterThan(PCMReader.duration(of: url), 1.0)
        let reader = try PCMReader(url: url)
        XCTAssertGreaterThan(reader.duration, 1.0)
        let skipped = try reader.skipSilence(from: 0)
        XCTAssertEqual(skipped, reader.duration, accuracy: 0.05)
        XCTAssertFalse(try reader.containsAudibleAudio())
        XCTAssertNil(try reader.slice(at: reader.duration + 1, length: 0.2))
    }

    func testToneIsAudibleAfterResample() throws {
        let url = try writeTone(seconds: 1.0, rate: 48_000)
        XCTAssertFalse(AudioFileIO.looksEmpty(url))
        let reader = try PCMReader(url: url)
        XCTAssertTrue(try reader.containsAudibleAudio())
        let slice = try reader.slice(at: 0.2, length: 0.25)
        XCTAssertNotNil(slice)
        XCTAssertGreaterThan(slice!.rms, 0.02)
    }

    func test48kHzSequentialSlicesKeepEnergy() throws {
        let url = try writeTone(seconds: 1.2, rate: 48_000)
        let reader = try PCMReader(url: url)
        var seen = 0
        var t: TimeInterval = 0
        while t < 1.0 {
            let piece = try reader.slice(at: t, length: 0.22)
            XCTAssertNotNil(piece, "slice at \(t)")
            XCTAssertGreaterThan(piece!.buffer.frameLength, 1_000)
            XCTAssertEqual(piece!.buffer.format.sampleRate, 16_000, accuracy: 1)
            XCTAssertGreaterThan(piece!.rms, 0.02)
            seen += 1
            t += 0.22
        }
        XCTAssertGreaterThanOrEqual(seen, 4)
        XCTAssertEqual(try reader.skipSilence(from: 0), 0, accuracy: 0.2)
    }

    func testHardwareTapFormatConvertsRepeatedly() throws {
        let session = PCMConvert()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ) else {
            XCTFail("format")
            return
        }
        let frames: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            XCTFail("buffer")
            return
        }
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for i in 0..<Int(frames) {
            let s = Float(sin(2 * Double.pi * 440 * Double(i) / 48_000) * 0.2)
            left[i] = s
            right[i] = s
        }
        var produced = 0
        var skipped = 0
        for _ in 0..<60 {
            guard let converted = session.convert(buffer) else {
                skipped += 1
                continue
            }
            XCTAssertEqual(converted.format.sampleRate, 48_000)
            XCTAssertEqual(converted.format.channelCount, 1)
            XCTAssertGreaterThan(PCMReader.rms(of: converted), 0.02)
            produced += Int(converted.frameLength)
        }
        XCTAssertLessThan(skipped, 4)
        XCTAssertGreaterThan(produced, 16_000)
    }

    func testCompactLeavesEmptyFileAlone() async throws {
        let tiny = folder.appendingPathComponent("empty.caf")
        try Data(repeating: 0, count: 16).write(to: tiny)
        let result = try await AudioCompressor.compactIfNeeded(url: tiny)
        XCTAssertEqual(result.path, tiny.path)
    }

    func testCompactCopiesCAFToM4AAndPreservesOriginal() async throws {
        let caf = try writeTone(seconds: 8.0, rate: 48_000)
        let created = LectureFileStamp.fileCreationDate(at: caf.path)
        let original = try Data(contentsOf: caf)
        let cafSize = AudioFileIO.fileSize(caf)
        let dest = try await AudioCompressor.compactIfNeeded(url: caf)
        XCTAssertEqual(dest.pathExtension.lowercased(), "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(AudioFileIO.looksEmpty(dest))
        XCTAssertTrue(FileManager.default.fileExists(atPath: caf.path))
        XCTAssertEqual(try Data(contentsOf: caf), original)
        let second = try await AudioCompressor.compactIfNeeded(url: caf)
        XCTAssertNotEqual(second, dest)
        XCTAssertEqual(try Data(contentsOf: caf), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let file = try AVAudioFile(forReading: dest)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000, accuracy: 1)
        let seconds = PCMReader.duration(of: dest)
        XCTAssertGreaterThan(seconds, 7.0)
        let bits = Double(AudioFileIO.fileSize(dest)) * 8 / seconds
        // HE 24k 是目标，LC 64k 是编码器不给时的退路。
        XCTAssertGreaterThan(bits, 14_000)
        XCTAssertLessThan(bits, 96_000)
        // 48 kHz 16-bit 原件是 768 kbps，压完至少要小一个数量级。
        XCTAssertLessThan(AudioFileIO.fileSize(dest) * 8, cafSize)
        XCTAssertEqual(
            LectureFileStamp.fileCreationDate(at: dest.path)?.timeIntervalSince1970 ?? 0,
            created?.timeIntervalSince1970 ?? -1,
            accuracy: 2
        )
    }

    /// macOS 27 上 `AVURLAssetPreferPreciseDurationAndTimingKey=false` 会让读轨道报
    /// -11800 / -17770，压缩整条路径失败。这里锁住「CAF 能读出音轨」这一步。
    func testAssetTracksLoadForRecordedCAF() async throws {
        let caf = try writeTone(seconds: 2.0, rate: 48_000)
        let tracks = try await AVURLAsset(url: caf).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
    }

    func testCompactLeavesExistingM4AAlone() async throws {
        let caf = try writeTone(seconds: 1.5, rate: 48_000)
        let dest = try await AudioCompressor.compactIfNeeded(url: caf)
        let size = AudioFileIO.fileSize(dest)
        let again = try await AudioCompressor.compactIfNeeded(url: dest)
        XCTAssertEqual(again.path, dest.path)
        XCTAssertEqual(AudioFileIO.fileSize(again), size)
    }

    private func writeTone(seconds: Double, rate: Double) throws -> URL {
        let url = folder.appendingPathComponent("\(UUID().uuidString).caf")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "test", code: 1)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "test", code: 2)
        }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        let hz = 440.0
        for i in 0..<Int(frames) {
            data[i] = Float(sin(2 * Double.pi * hz * Double(i) / rate) * 0.25)
        }
        try file.write(from: buffer)
        return url
    }

    private func writeSilence(seconds: Double) throws -> URL {
        let url = folder.appendingPathComponent("\(UUID().uuidString).caf")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "test", code: 1)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = AVAudioFrameCount(16_000 * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "test", code: 2)
        }
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }
}
