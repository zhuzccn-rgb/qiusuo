import AVFoundation
import Accelerate
import Foundation

/// Sequential 16 kHz mono PCM from a lecture file. Cursor is in seconds of source audio.
public final class PCMReader: @unchecked Sendable {
    public static let targetRate: Double = 16_000

    public let duration: TimeInterval
    public let sourceRate: Double

    private let file: AVAudioFile
    private let source: AVAudioFormat
    private let target: AVAudioFormat
    private let converter: AVAudioConverter?
    private var converterCursor: AVAudioFramePosition = -1
    private let lock = NSLock()

    public init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { throw RecorderError.startFailed }
        self.file = file
        self.source = file.processingFormat
        self.sourceRate = rate
        self.duration = file.length > 0 ? Double(file.length) / rate : 0
        self.target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetRate,
            channels: 1,
            interleaved: false
        ) ?? file.processingFormat
        self.converter = Self.sameFormat(file.processingFormat, self.target)
            ? nil
            : AVAudioConverter(from: file.processingFormat, to: self.target)
    }

    public static func duration(of url: URL) -> TimeInterval {
        let fromFile: TimeInterval = autoreleasepool {
            guard let audio = try? AVAudioFile(forReading: url) else { return 0 }
            let rate = audio.processingFormat.sampleRate
            guard rate > 0 else { return 0 }
            let seconds = Double(audio.length) / rate
            return (seconds.isFinite && seconds > 0) ? seconds : 0
        }
        if fromFile > 0 { return fromFile }
        return autoreleasepool {
            let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            return seconds.isFinite && seconds > 0 ? seconds : 0
        }
    }

    public func slice(at seconds: TimeInterval, length: TimeInterval) throws -> (buffer: AVAudioPCMBuffer, rms: Float)? {
        lock.lock()
        defer { lock.unlock() }
        guard seconds < duration, length > 0 else { return nil }
        let start = AVAudioFramePosition(max(0, seconds * sourceRate))
        guard start < file.length else { return nil }
        let frames = min(
            AVAudioFrameCount(length * sourceRate),
            AVAudioFrameCount(file.length - start)
        )
        guard frames > 0 else { return nil }
        file.framePosition = start
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else { return nil }
        try file.read(into: inBuf, frameCount: frames)
        guard inBuf.frameLength > 0 else { return nil }

        let pcm: AVAudioPCMBuffer
        if converter != nil {
            if converterCursor >= 0, abs(start - converterCursor) > 1 {
                converter?.reset()
            }
            guard let converted = try resample(inBuf) else { return nil }
            pcm = converted
        } else {
            pcm = inBuf
        }
        converterCursor = start + AVAudioFramePosition(inBuf.frameLength)
        guard pcm.frameLength > 0 else { return nil }
        let raw = Self.rms(of: pcm)
        return (pcm, raw)
    }

    /// Keep the resampler across contiguous slices. `reset()` + `endOfStream` on every
    /// 0.22 s window drops the first 48 kHz→16 kHz packet (empty RMS), so Speech waits
    /// forever on the opening utterance.
    private func resample(_ inBuf: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard let converter else { return inBuf }
        let ratio = target.sampleRate / max(source.sampleRate, 1)
        let needed = AVAudioFrameCount(ceil(Double(inBuf.frameLength) * ratio) + 512)
        guard let dest = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: needed) else { return nil }
        let packet = OnceBuffer(inBuf)
        var error: NSError?
        let status = converter.convert(to: dest, error: &error) { _, outStatus in
            packet.supply(outStatus)
        }
        if status == .error {
            converter.reset()
            converterCursor = -1
            throw error ?? NSError(domain: "PCMReader", code: -1)
        }
        return dest
    }

    public func skipSilence(from seconds: TimeInterval) throws -> TimeInterval {
        var t = seconds
        var steps = 0
        while t < duration {
            steps += 1
            if steps > 20_000 { return duration }
            guard let piece = try slice(at: t, length: 0.35) else {
                t += 0.35
                continue
            }
            if piece.rms >= 0.0012 { return max(seconds, t - 0.12) }
            t += 0.35
        }
        return duration
    }

    /// True if any sampled window has energy. All-zero CAFs have a duration but no speech.
    public func containsAudibleAudio(threshold: Float = 0.001) throws -> Bool {
        var t: TimeInterval = 0
        while t < min(duration, 45) {
            if let piece = try slice(at: t, length: 0.35), piece.rms >= threshold {
                return true
            }
            t += 0.35
        }
        t = 45
        while t < duration {
            if let piece = try slice(at: t, length: 0.35), piece.rms >= threshold {
                return true
            }
            t += 20
        }
        return false
    }

    public static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let n = vDSP_Length(buffer.frameLength)
        guard n > 0 else { return 0 }
        if let data = buffer.floatChannelData?[0] {
            var value: Float = 0
            vDSP_rmsqv(data, 1, &value, n)
            return value
        }
        if let data = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            let count = Int(buffer.frameLength)
            for i in 0..<count {
                let s = Float(data[i]) / 32_768
                sum += s * s
            }
            return sqrtf(sum / Float(count))
        }
        return 0
    }

    private static func sameFormat(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
    }
}

private final class OnceBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func supply(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if let buffer {
            self.buffer = nil
            status.pointee = .haveData
            return buffer
        }
        status.pointee = .noDataNow
        return nil
    }
}

/// Hardware mics are often 48 kHz stereo. Archive PCM is 48 kHz mono float.
/// Speech still resamples to 16 kHz in `PCMReader`.
public final class PCMConvert: @unchecked Sendable {
    public static let targetRate: Double = 48_000

    private let outFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterKey = ""
    private var outBuffer: AVAudioPCMBuffer

    public init() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetRate,
            channels: 1,
            interleaved: false
        )!
        outFormat = format
        outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768)!
    }

    public func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        let inFormat = buffer.format
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { return nil }

        if inFormat.sampleRate == outFormat.sampleRate,
           inFormat.channelCount == outFormat.channelCount,
           inFormat.commonFormat == outFormat.commonFormat,
           inFormat.isInterleaved == outFormat.isInterleaved {
            return buffer
        }

        if let converted = convertWithUnit(buffer) { return converted }
        if let mixed = mixToMonoFloat(buffer) {
            if mixed.format.sampleRate == outFormat.sampleRate,
               mixed.format.commonFormat == outFormat.commonFormat {
                return mixed
            }
            return convertWithUnit(mixed)
        }
        return nil
    }

    private func convertWithUnit(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let inFormat = buffer.format
        let key = "\(inFormat.sampleRate)|\(inFormat.channelCount)|\(inFormat.commonFormat.rawValue)|\(inFormat.isInterleaved)"
        if converter == nil || converterKey != key {
            converter = AVAudioConverter(from: inFormat, to: outFormat)
            converterKey = key
        }
        guard let converter else { return nil }

        let ratio = outFormat.sampleRate / max(inFormat.sampleRate, 1)
        let needed = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio) + 256)
        if needed > outBuffer.frameCapacity {
            guard let bigger = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: needed) else { return nil }
            outBuffer = bigger
        }
        outBuffer.frameLength = outBuffer.frameCapacity

        var provided = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if !provided {
                provided = true
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        if status == .error {
            self.converter = nil
            return nil
        }
        if outBuffer.frameLength == 0 {
            return nil
        }
        return outBuffer
    }

    private func mixToMonoFloat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return nil }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ), let dest = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        dest.frameLength = frames
        let out = dest.floatChannelData![0]
        let n = Int(frames)

        if buffer.format.isInterleaved {
            if let data = buffer.floatChannelData?[0] {
                for i in 0..<n {
                    var sum: Float = 0
                    for c in 0..<channels { sum += data[i * channels + c] }
                    out[i] = sum / Float(channels)
                }
                return dest
            }
            if let data = buffer.int16ChannelData?[0] {
                for i in 0..<n {
                    var sum: Float = 0
                    for c in 0..<channels { sum += Float(data[i * channels + c]) / 32_768 }
                    out[i] = sum / Float(channels)
                }
                return dest
            }
        } else if let planes = buffer.floatChannelData {
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += planes[c][i] }
                out[i] = sum / Float(channels)
            }
            return dest
        } else if let planes = buffer.int16ChannelData {
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += Float(planes[c][i]) / 32_768 }
                out[i] = sum / Float(channels)
            }
            return dest
        }
        return nil
    }
}
