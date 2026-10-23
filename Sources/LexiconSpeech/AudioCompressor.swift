import AVFoundation
import Foundation
import LexiconCore

public enum AudioFileIO {
    /// `kAudioFileInvalidFileError` / FourCC `dta?`
    public static let invalidFileCode = 1_685_348_671

    public static func isInvalid(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.code == invalidFileCode
            || (ns.domain == NSOSStatusErrorDomain && ns.code == invalidFileCode)
            || (ns.domain == AVFoundationErrorDomain && ns.code == invalidFileCode)
    }

    public static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Prefer duration when the decoder can read it. Size is only a fallback so a
    /// short AAC file is not treated as empty, and a huge unreadable blob is kept.
    public static func looksEmpty(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        let size = fileSize(url)
        if size == 0 { return true }
        let duration = PCMReader.duration(of: url)
        if duration >= 0.4 { return false }
        if size < 2048 { return true }
        return size < 64_000
    }

    public static func message(for error: Error) -> String {
        if isInvalid(error) {
            return "录音文件是空的或没写完，无法转写。请重新录这一段。"
        }
        return error.localizedDescription
    }
}

/// Streamed AAC recompress. Does not load the whole lecture into RAM.
public enum AudioCompressor {
    public static let archiveSampleRate = 48_000
    public static let archiveBitRate = 24_000

    /// 转写之后才压。同一段 48 分钟真实课堂实测（段信噪比，越高越接近原声）：
    /// HE 24k 10.8 MB/小时 16.0 dB，LC 32k 14.6 MB/小时 15.7 dB，LC 64k 27.8 MB/小时 26.7 dB。
    /// HE 比同档 LC 更小也更准，所以默认 HE；编码器不给就退回 LC 64k，宁可大也不要压失败。
    static let targets: [[String: Any]] = [
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC_HE),
            AVSampleRateKey: archiveSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: archiveBitRate
        ],
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: archiveSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
    ]

    /// Non-destructive copy: CAF → HE-AAC 48 kHz ~24 kbps mono. Existing m4a is left alone
    /// (old 16 kbps files cannot be restored; new archives must not be crushed again).
    public static func compactIfNeeded(url: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        if AudioFileIO.looksEmpty(url) { return url }
        let duration = PCMReader.duration(of: url)
        guard duration > 0.5 else { return url }
        if url.pathExtension.lowercased() == "m4a" { return url }

        let base = url.deletingPathExtension()
        var dest = base.appendingPathExtension("m4a")
        var index = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent)-\(index).m4a")
            index += 1
        }
        let created = LectureFileStamp.recordedAt(filePath: url.path)
        var lastError: Error?
        var written = false
        for settings in targets {
            do {
                try await transcode(from: url, to: dest, settings: settings)
                try verifyUsable(dest)
                written = true
                break
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: dest)
            }
        }
        guard written else {
            throw lastError ?? RecorderError.compressFailed
        }
        if let created {
            LectureFileStamp.applyCreationDate(created, to: dest.path)
        }
        // Compression makes a separate copy. Only an explicit user action may delete originals.
        return dest
    }

    private static func verifyUsable(_ url: URL) throws {
        if AudioFileIO.looksEmpty(url) { throw RecorderError.compressFailed }
    }

    private static func transcode(from source: URL, to dest: URL, settings: [String: Any]) async throws {
        // 不要传 AVURLAssetPreferPreciseDurationAndTimingKey=false：macOS 27 上读轨道会直接报
        // -11800 / OSStatus -17770（assetProperty_Tracks），压缩整条路径都会失败。
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw RecorderError.startFailed }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            do {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(
                    track: track,
                    outputSettings: [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                )
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else {
                    once.go { cont.resume(throwing: RecorderError.startFailed) }
                    return
                }
                reader.add(output)

                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                let writer = try AVAssetWriter(outputURL: dest, fileType: .m4a)
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else {
                    once.go { cont.resume(throwing: RecorderError.startFailed) }
                    return
                }
                writer.add(input)

                guard writer.startWriting(), reader.startReading() else {
                    once.go { cont.resume(throwing: writer.error ?? reader.error ?? RecorderError.startFailed) }
                    return
                }
                writer.startSession(atSourceTime: .zero)

                let queue = DispatchQueue(label: "app.lexicon.audio.compress", qos: .utility)
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        if reader.status == .failed {
                            input.markAsFinished()
                            writer.cancelWriting()
                            once.go { cont.resume(throwing: reader.error ?? RecorderError.startFailed) }
                            return
                        }
                        if let sample = output.copyNextSampleBuffer() {
                            if !input.append(sample) {
                                input.markAsFinished()
                                writer.cancelWriting()
                                once.go { cont.resume(throwing: writer.error ?? RecorderError.startFailed) }
                                return
                            }
                            continue
                        }
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .failed {
                                once.go { cont.resume(throwing: writer.error ?? RecorderError.startFailed) }
                            } else {
                                once.go { cont.resume() }
                            }
                        }
                        return
                    }
                }
            } catch {
                once.go { cont.resume(throwing: error) }
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func go(_ work: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { work() }
    }
}
