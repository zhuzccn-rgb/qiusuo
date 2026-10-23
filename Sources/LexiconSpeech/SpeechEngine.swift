import AVFoundation
import CoreMedia
import Foundation
import Speech
import LexiconCore

/// On-device speech recognition. Apple Speech finalizes at the first pause, so
/// we step utterance-by-utterance using segment timestamps instead of skipping
/// the rest of a 25-second window.
public final class SpeechEngine: ObservableObject {
    @Published public private(set) var isTranscribing = false
    @Published public private(set) var progressText = ""
    private var activeTask: SFSpeechRecognitionTask?
    private var heldRecognizer: SFSpeechRecognizer?
    private let cancelFlag = StopFlag()
    private var transcribeActivity: NSObjectProtocol?

    public init() {}

    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    public func cancel() {
        cancelFlag.on()
        Task { @MainActor in
            self.activeTask?.cancel()
        }
    }

    public func transcribe(
        file url: URL,
        localeIdentifier: String,
        onPartial: ((String, TimeInterval) -> Void)? = nil
    ) async throws -> String {
        let status = await requestAuthorization()
        guard status == .authorized else { throw SpeechEngineError.notAuthorized }

        cancelFlag.reset()
        beginTranscribeActivity()
        await publish(busy: true, text: "正在转写…")
        do {
            let text = try await transcribeFile(url, localeIdentifier: localeIdentifier, onPartial: onPartial)
            await finishSession()
            return text
        } catch {
            await finishSession()
            throw error
        }
    }

    private func transcribeFile(
        _ url: URL,
        localeIdentifier: String,
        onPartial: ((String, TimeInterval) -> Void)?
    ) async throws -> String {
        let reader: PCMReader
        do {
            reader = try PCMReader(url: url)
        } catch {
            throw SpeechEngineError.invalidAudio(AudioFileIO.message(for: error))
        }
        if reader.duration < 0.4 {
            throw SpeechEngineError.invalidAudio("录音没有有效音频（时长为 0）。请重新录这一段。")
        }
        await publish(busy: true, text: "正在检查录音…")
        if !(try reader.containsAudibleAudio()) {
            throw SpeechEngineError.invalidAudio("这份录音是静音（有时长，但样本全是 0），没法转写。不是听写包的问题，请重新录。")
        }
        if #available(macOS 26.0, *), SpeechTranscriber.isAvailable {
            return try await transcribeWithAnalyzer(
                url: url,
                localeIdentifier: localeIdentifier,
                duration: reader.duration,
                onPartial: onPartial
            )
        }
        return try await transcribeByUtterance(
            reader: reader,
            localeIdentifier: localeIdentifier,
            onPartial: onPartial
        )
    }

    private func transcribeByUtterance(
        reader: PCMReader,
        localeIdentifier: String,
        onPartial: ((String, TimeInterval) -> Void)?
    ) async throws -> String {
        let locales = Self.localeCandidates(preferred: localeIdentifier)
        var localeIndex = 0
        var noSpeechStreak = 0
        var parts: [String] = []
        var cursor: TimeInterval = 0
        var lastText = ""
        let total = Self.clock(reader.duration)

        while cursor < reader.duration {
            if cancelFlag.isOn { break }
            let marked = cursor
            await publish(busy: true, text: "转写 \(Self.clock(cursor)) / \(total)")
            cursor = try UtteranceSilenceSkip.skipLeading(reader: reader, from: cursor)
            if cursor >= reader.duration { break }

            let locale = locales[min(localeIndex, locales.count - 1)]
            if cursor != marked {
                await publish(busy: true, text: "转写 \(Self.clock(cursor)) / \(total)")
            }

            do {
                let utterance = try await recognizeUtterance(
                    reader: reader,
                    at: cursor,
                    localeIdentifier: locale
                )
                if utterance.text.isEmpty || utterance.seconds < 0.2 {
                    noSpeechStreak += 1
                    cursor += 1.6
                    if noSpeechStreak >= 3, localeIndex + 1 < locales.count {
                        localeIndex += 1
                    }
                } else {
                    noSpeechStreak = 0
                    let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, text != lastText {
                        if !lastText.isEmpty, text.hasPrefix(lastText), !parts.isEmpty {
                            parts[parts.count - 1] = text
                        } else if lastText.hasSuffix(text) {
                            // repeat of a fragment already captured
                        } else {
                            parts.append(text)
                        }
                        lastText = text
                    }
                    onPartial?(parts.reduce("") { TranscriptStitch.append($0, $1) }, cursor)
                    cursor += max(utterance.seconds - 0.12, 0.35)
                }
            } catch {
                if Self.isNoSpeech(error) {
                    noSpeechStreak += 1
                    cursor += 1.6
                    if noSpeechStreak >= 3, localeIndex + 1 < locales.count {
                        localeIndex += 1
                    }
                } else {
                    throw SpeechEngineError.speechKit(error.localizedDescription)
                }
            }
            if cursor <= marked { cursor = marked + 0.35 }
        }

        let joined = parts.reduce("") { TranscriptStitch.append($0, $1) }
        if cancelFlag.isOn {
            if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SpeechEngineError.cancelled
            }
            return joined
        }
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechEngineError.emptyResult
        }
        return joined
    }

    @MainActor
    private func publish(busy: Bool, text: String) {
        isTranscribing = busy
        progressText = busy ? text : ""
    }

    @MainActor
    private func finishSession() {
        activeTask?.cancel()
        activeTask = nil
        isTranscribing = false
        progressText = ""
        endTranscribeActivity()
    }

    private func beginTranscribeActivity() {
        endTranscribeActivity()
        transcribeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "求索正在转写"
        )
    }

    private func endTranscribeActivity() {
        if let transcribeActivity {
            ProcessInfo.processInfo.endActivity(transcribeActivity)
            self.transcribeActivity = nil
        }
    }

    private static func localeCandidates(preferred: String) -> [String] {
        var list = [preferred]
        if preferred != "en-US" { list.append("en-US") }
        return list
    }

    static func isNoSpeech(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.localizedDescription.localizedCaseInsensitiveContains("no speech") { return true }
        return ns.domain.contains("Assistant") && (ns.code == 1110 || ns.code == 203)
    }

    private static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    @available(macOS 26.0, *)
    private func transcribeWithAnalyzer(
        url: URL,
        localeIdentifier: String,
        duration: TimeInterval,
        onPartial: ((String, TimeInterval) -> Void)?
    ) async throws -> String {
        let requested = Locale(identifier: localeIdentifier)
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) ?? requested
        let supported = await SpeechTranscriber.supportedLocales
        let supportedIDs = Set(supported.map { $0.identifier(.bcp47) })
        guard supportedIDs.contains(locale.identifier(.bcp47)) || supportedIDs.contains(requested.identifier(.bcp47)) else {
            throw SpeechEngineError.localeUnavailable(localeIdentifier)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [.etiquetteReplacements],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureAnalyzerAssets(for: transcriber)
        if cancelFlag.isOn { throw SpeechEngineError.cancelled }

        let file = try AVAudioFile(forReading: url)
        // 2b stays off until a same-file A/B shows Analyzer+SpeechDetector is not worse.
        let analyzer = try await makeAnalyzer(transcriber: transcriber)
        let total = Self.clock(duration)
        await publish(busy: true, text: "转写 0:00 / \(total)")

        let collect = Task { () -> String in
            var text = ""
            var lastEnd: TimeInterval = 0
            for try await result in transcriber.results {
                if self.cancelFlag.isOn { break }
                guard result.isFinal else { continue }
                let piece = String(result.text.characters)
                let start = CMTimeGetSeconds(result.range.start)
                text = TranscriptStitch.appendSegment(
                    existing: text,
                    incoming: piece,
                    start: start,
                    previousEnd: lastEnd
                )
                let end = CMTimeGetSeconds(result.range.end)
                if end.isFinite { lastEnd = max(lastEnd, end) }
                await self.publish(busy: true, text: "转写 \(Self.clock(lastEnd)) / \(total)")
                onPartial?(text, lastEnd)
            }
            return text
        }

        let watchCancel = Task {
            while !self.cancelFlag.isOn {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
            }
            await analyzer.cancelAndFinishNow()
        }

        do {
            try await runAnalyzer(analyzer, file: file)
        } catch {
            watchCancel.cancel()
            await analyzer.cancelAndFinishNow()
            if cancelFlag.isOn { throw SpeechEngineError.cancelled }
            if Self.attachSpeechDetectorToAnalyzer {
                do {
                    file.framePosition = 0
                    let fallback = SpeechAnalyzer(modules: [transcriber])
                    try await runAnalyzer(fallback, file: file)
                } catch {
                    if cancelFlag.isOn { throw SpeechEngineError.cancelled }
                    throw SpeechEngineError.speechKit(error.localizedDescription)
                }
            } else {
                throw SpeechEngineError.speechKit(error.localizedDescription)
            }
        }
        watchCancel.cancel()

        if cancelFlag.isOn {
            let partial = (try? await collect.value) ?? ""
            if partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SpeechEngineError.cancelled
            }
            return partial
        }

        let joined = try await collect.value
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechEngineError.emptyResult
        }
        return joined
    }

    /// Phase 2b: do not flip this on without a same-file A/B against Analyzer alone.
    private static let attachSpeechDetectorToAnalyzer = false

    @available(macOS 26.0, *)
    private func makeAnalyzer(transcriber: SpeechTranscriber) async throws -> SpeechAnalyzer {
        guard Self.attachSpeechDetectorToAnalyzer else {
            return SpeechAnalyzer(modules: [transcriber])
        }
        let detector = SpeechDetector(
            detectionOptions: SpeechDetector.DetectionOptions(sensitivityLevel: .medium),
            reportResults: false
        )
        return SpeechAnalyzer(modules: [transcriber, detector])
    }

    @available(macOS 26.0, *)
    private func runAnalyzer(_ analyzer: SpeechAnalyzer, file: AVAudioFile) async throws {
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    @available(macOS 26.0, *)
    private func ensureAnalyzerAssets(for transcriber: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .unsupported {
            throw SpeechEngineError.localeUnavailable(transcriber.selectedLocales.first?.identifier ?? "en-US")
        }
        if status == .installed { return }
        await publish(busy: true, text: "正在下载听写模型（只需一次）…")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private func recognizeUtterance(
        reader: PCMReader,
        at start: TimeInterval,
        localeIdentifier: String
    ) async throws -> (text: String, seconds: TimeInterval) {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let recognizer: SFSpeechRecognizer
                do {
                    recognizer = try self.recognizer(for: localeIdentifier)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.requiresOnDeviceRecognition = true
                request.taskHint = .dictation
                if #available(macOS 14.0, *) {
                    request.addsPunctuation = true
                }

                let box = UtteranceBox()
                let gate = ResumeGate()
                let stop = StopFlag()
                let cancelFlag = self.cancelFlag

                self.activeTask?.cancel()
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        box.update(result, sampleRate: PCMReader.targetRate)
                        if result.isFinal {
                            stop.on()
                            gate.go { continuation.resume(returning: box.snapshot()) }
                        }
                    }
                    if let error {
                        stop.on()
                        gate.go {
                            if box.text.isEmpty {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: box.snapshot())
                            }
                        }
                        return
                    }
                    if result == nil {
                        stop.on()
                        gate.go { continuation.resume(returning: box.snapshot()) }
                    }
                }
                self.activeTask = task

                let watchdog = Task {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    stop.on()
                    await MainActor.run {
                        task.cancel()
                        request.endAudio()
                    }
                    gate.go { continuation.resume(returning: ("", 0)) }
                }

                Task.detached {
                    defer { watchdog.cancel() }
                    var fed: TimeInterval = 0
                    let slice: TimeInterval = 0.22
                    let maxFeed: TimeInterval = 18
                    do {
                        while fed < maxFeed, !stop.isOn, !cancelFlag.isOn {
                            guard let piece = try reader.slice(at: start + fed, length: slice) else { break }
                            if piece.buffer.frameLength == 0 { break }
                            if fed > 1.0, piece.rms < 0.003, box.text.isEmpty {
                                break
                            }
                            request.append(piece.buffer)
                            fed += Double(piece.buffer.frameLength) / PCMReader.targetRate
                            try await Task.sleep(nanoseconds: 12_000_000)
                        }
                        stop.on()
                        if box.text.isEmpty, !box.isFinal {
                            await MainActor.run { task.cancel() }
                            gate.go { continuation.resume(returning: ("", 0)) }
                            return
                        }
                        request.endAudio()
                    } catch {
                        stop.on()
                        gate.go { continuation.resume(throwing: error) }
                        return
                    }
                    for _ in 0..<6 {
                        if cancelFlag.isOn || box.isFinal { break }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                    gate.go { continuation.resume(returning: box.snapshot()) }
                }
            }
        }
    }

    @MainActor
    private func recognizer(for localeIdentifier: String) throws -> SFSpeechRecognizer {
        if let held = heldRecognizer, held.locale.identifier == localeIdentifier, held.isAvailable {
            return held
        }
        guard let created = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              created.isAvailable else {
            throw SpeechEngineError.localeUnavailable(localeIdentifier)
        }
        heldRecognizer = created
        return created
    }
}

private final class UtteranceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _text = ""
    private var _seconds: TimeInterval = 0
    private var _final = false

    var isFinal: Bool {
        lock.lock(); defer { lock.unlock() }
        return _final
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return _text
    }

    func update(_ result: SFSpeechRecognitionResult, sampleRate: Double) {
        let text = result.bestTranscription.formattedString
        var seconds: TimeInterval = 0
        if let last = result.bestTranscription.segments.last {
            let end = last.timestamp + last.duration
            if end > 0.12 { seconds = end }
        }
        if seconds < 0.12 {
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            seconds = max(0.45, Double(words) / 2.5)
        }
        lock.lock()
        if text.count >= _text.count { _text = text }
        if seconds > _seconds { _seconds = seconds }
        if result.isFinal { _final = true }
        lock.unlock()
        _ = sampleRate
    }

    func snapshot() -> (text: String, seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _final = true
        return (_text, _seconds)
    }
}

private final class StopFlag: @unchecked Sendable {
    private var onFlag = false
    private let lock = NSLock()
    var isOn: Bool {
        lock.lock(); defer { lock.unlock() }
        return onFlag
    }
    func on() {
        lock.lock()
        onFlag = true
        lock.unlock()
    }
    func reset() {
        lock.lock()
        onFlag = false
        lock.unlock()
    }
}

private final class ResumeGate: @unchecked Sendable {
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

public enum SpeechEngineError: LocalizedError {
    case notAuthorized
    case localeUnavailable(String)
    case emptyResult
    case invalidAudio(String)
    case speechKit(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未授权语音识别。请在系统设置 → 隐私与安全性 → 语音识别中允许「求索」。"
        case .localeUnavailable(let id):
            return "系统没有安装 \(id) 的离线语音包。打开系统设置 → 键盘 → 听写，下载 English（United States）。"
        case .emptyResult:
            return "没有识别到语音。请确认麦克风有声音后再转写。"
        case .invalidAudio(let message):
            return message
        case .speechKit(let message):
            return message
        case .cancelled:
            return "已停止转写。"
        }
    }
}
