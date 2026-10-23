import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import LexiconCore

public final class AudioRecorder: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var framesWritten: AVAudioFramePosition = 0
    @Published public private(set) var capturedPeak: Float = 0
    @Published public private(set) var isStalled = false
    @Published public private(set) var voiceProcessingActive = false
    @Published public private(set) var inputDeviceName = ""
    @Published public private(set) var needsAutoSave = false
    public private(set) var droppedVoiceProcessing = false

    private var engine: AVAudioEngine?
    private var writer: RecordingWriter?
    private var selectedInput: AudioInputDevice?
    private var voiceProcessingRequested = false
    private var voiceProcessingUnavailable = false
    private var silenceGraceUntil = Date.distantPast
    private var timer: Timer?
    private var startedAt: Date?
    private var fileURL: URL?
    private var sleepActivity: NSObjectProtocol?
    private var tapInstalled = false
    private var recovering = false
    private var lastRecoverAt: Date?
    private var lastProgressAt: Date?
    private var lastProgressFrames: AVAudioFramePosition = 0
    private var engineObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let preroll = Preroll()

    public var capturedSeconds: TimeInterval { Double(framesWritten) / RecordingWriter.targetRate }

    public override init() {
        super.init()
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recoverEngine(reason: "系统唤醒")
        })
        workspaceObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording, self.isStalled else { return }
            self.recoverEngine(reason: "重新激活")
        })
    }

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        clearEngineObserver()
        endSleepAssertion()
        enableAppExit()
    }

    public func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Opens the input device before a file exists. Navigation, startup, and stop must not call this.
    public func prime() {
        guard !isRecording else { return }
        if engine?.isRunning == true { return }
        if selectedInput == nil {
            selectedInput = AudioInputPicker.lectureMic()
            inputDeviceName = selectedInput?.name ?? ""
        }
        try? assembleEngine(creatingWriter: false, useVoiceProcessing: false, discardTap: true)
    }

    public func unprime() {
        guard !isRecording else { return }
        detachEngine(closeWriter: false)
        preroll.clear()
        selectedInput = nil
        inputDeviceName = ""
    }

    public func start(voiceProcessing: Bool = false) throws -> URL {
        if isRecording {
            throw RecorderError.alreadyRecording
        }

        let allowed = AVCaptureDevice.authorizationStatus(for: .audio)
        if allowed != .authorized {
            throw RecorderError.noMicrophone
        }

        let url = AppPaths.recordingsDirectory.appendingPathComponent("\(ISO8601.fileNow).caf")
        fileURL = url
        selectedInput = AudioInputPicker.lectureMic()
        inputDeviceName = selectedInput?.name ?? ""
        voiceProcessingRequested = voiceProcessing
        voiceProcessingUnavailable = false
        voiceProcessingActive = false
        silenceGraceUntil = Date.distantPast
        droppedVoiceProcessing = false
        lastError = nil
        needsAutoSave = false
        beginSleepAssertion()
        disableAppExit()
        do {
            if engine?.isRunning == true {
                try attachWriterToRunningEngine()
            } else {
                try attachEngine(creatingWriter: true)
            }
        } catch {
            teardownSession(keepFile: false)
            if error is RecorderError { throw error }
            throw RecorderError.startFailed
        }

        startedAt = Date()
        isRecording = true
        elapsed = 0
        framesWritten = 0
        capturedPeak = 0
        isStalled = false
        lastProgressAt = Date()
        lastProgressFrames = 0
        // Keep a fallback note from attachEngine; do not wipe it.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        return url
    }

    @discardableResult
    public func stop() throws -> URL? {
        timer?.invalidate()
        timer = nil
        let url = fileURL
        let snap = writer?.snapshot()
        framesWritten = snap?.frames ?? 0
        capturedPeak = snap?.peak ?? 0
        if let err = snap?.error { lastError = err }
        detachEngine(closeWriter: true)
        teardownSession(keepFile: true)
        isRecording = false
        isStalled = false
        needsAutoSave = false
        voiceProcessingActive = false
        selectedInput = nil
        inputDeviceName = ""
        fileURL = nil
        startedAt = nil
        if framesWritten == 0 {
            lastError = lastError ?? "录音计时在走，但麦克风数据没有写入文件。"
        } else if capturedPeak < 0.0008 {
            lastError = lastError ?? "麦克风写入的全是静音。请检查输入设备后重录。"
        }
        return url
    }

    private func tick() {
        guard isRecording, let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        let snap = writer?.snapshot()
        framesWritten = snap?.frames ?? 0
        capturedPeak = snap?.peak ?? 0
        if let err = snap?.error {
            lastError = err
        }
        if framesWritten > lastProgressFrames {
            lastProgressFrames = framesWritten
            lastProgressAt = Date()
            isStalled = false
            if let err = snap?.error { lastError = err }
        } else {
            let idle = Date().timeIntervalSince(lastProgressAt ?? startedAt)
            if elapsed > 8, idle > 8 {
                isStalled = true
                lastError = framesWritten == 0
                    ? "计时在走，但还没有音频写入。正在尝试恢复麦克风…"
                    : "写入已停止。正在尝试恢复麦克风…"
                recoverEngine(reason: framesWritten == 0 ? "没有写入" : "写入中断")
            }
            if elapsed > 8, idle > 45, capturedSeconds > 0.5, !needsAutoSave {
                needsAutoSave = true
                lastError = "超过 45 秒没有新音频写入，将自动保存已经录到的部分。"
            }
        }
        guard capturedPeak < 0.0008, capturedSeconds > 0.5 else { return }
        if voiceProcessingActive, elapsed > 1.8 {
            fallbackToRawMic()
            return
        }
        if Date() >= silenceGraceUntil, elapsed > 4 {
            isStalled = true
            lastError = "麦克风写入的全是静音。当前输入是「\(inputDeviceName.isEmpty ? "系统默认" : inputDeviceName)」。请停止后在系统设置里改成 Mac 麦克风再录。"
        }
    }

    private func fallbackToRawMic() {
        guard isRecording, voiceProcessingActive, writer != nil, !recovering else { return }
        recovering = true
        lastRecoverAt = Date()
        voiceProcessingUnavailable = true
        droppedVoiceProcessing = true
        detachEngine(closeWriter: false)
        defer { recovering = false }
        do {
            try assembleEngine(creatingWriter: false, useVoiceProcessing: false)
            lastError = "系统人声处理录出来是静音，已改用原始麦克风。"
            silenceGraceUntil = Date().addingTimeInterval(5)
            isStalled = false
        } catch {
            lastError = "系统人声处理录出来是静音，切回原始麦失败。请停止后关掉该开关再录。"
            isStalled = true
        }
    }

    private func recoverEngine(reason: String) {
        guard isRecording, fileURL != nil, writer != nil, !recovering else { return }
        if let lastRecoverAt, Date().timeIntervalSince(lastRecoverAt) < 6 { return }
        recovering = true
        lastRecoverAt = Date()
        defer { recovering = false }
        detachEngine(closeWriter: false)
        do {
            try attachEngine(creatingWriter: false)
            isStalled = false
        } catch {
            lastError = "\(reason) 后无法继续写。请点停止再重新开始。"
            isStalled = true
        }
    }

    private func attachWriterToRunningEngine() throws {
        guard let engine, engine.isRunning else { throw RecorderError.startFailed }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if writer == nil {
            guard let url = fileURL else { throw RecorderError.startFailed }
            writer = try RecordingWriter(url: url)
        }
        guard let writer else { throw RecorderError.startFailed }
        preroll.flush(into: writer)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            writer.append(buffer)
        }
        tapInstalled = true
        listenForConfigurationChanges(engine)
        lastRecoverAt = Date()
    }

    private func attachEngine(creatingWriter: Bool) throws {
        let wantProcessing = voiceProcessingRequested && !voiceProcessingUnavailable
        do {
            try assembleEngine(creatingWriter: creatingWriter, useVoiceProcessing: wantProcessing)
        } catch {
            guard wantProcessing else { throw RecorderError.startFailed }
            voiceProcessingUnavailable = true
            Thread.sleep(forTimeInterval: 0.15)
            do {
                try assembleEngine(creatingWriter: writer == nil, useVoiceProcessing: false)
            } catch {
                throw RecorderError.startFailed
            }
            lastError = "系统人声处理开不了，已改用原始麦克风。"
            droppedVoiceProcessing = true
        }
    }

    private func assembleEngine(creatingWriter: Bool, useVoiceProcessing: Bool, discardTap: Bool = false) throws {
        detachEngine(closeWriter: false)
        preroll.clear()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        var processingOn = false
        var didTap = false
        do {
            bindInputDevice(input)
            if useVoiceProcessing {
                try input.setVoiceProcessingEnabled(true)
                processingOn = true
            }

            if discardTap {
                let preroll = self.preroll
                input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
                    preroll.push(buffer)
                }
                didTap = true
            } else {
                if writer == nil {
                    guard creatingWriter, let url = fileURL else { throw RecorderError.startFailed }
                    writer = try RecordingWriter(url: url)
                }
                guard let writer else { throw RecorderError.startFailed }
                input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
                    writer.append(buffer)
                }
                didTap = true
            }

            do {
                try engine.start()
            } catch {
                if processingOn { throw error }
                engine.connect(input, to: engine.mainMixerNode, format: nil)
                engine.mainMixerNode.outputVolume = 0
                try engine.start()
            }

            let hwFormat = input.outputFormat(forBus: 0)
            guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
                throw RecorderError.startFailed
            }

            tapInstalled = true
            voiceProcessingActive = processingOn
            self.engine = engine
            listenForConfigurationChanges(engine)
            lastRecoverAt = Date()
        } catch {
            if processingOn {
                try? input.setVoiceProcessingEnabled(false)
            }
            if didTap {
                input.removeTap(onBus: 0)
            }
            if engine.isRunning { engine.stop() }
            engine.reset()
            throw error
        }
    }

    private func bindInputDevice(_ input: AVAudioInputNode) {
        guard let id = selectedInput?.id else { return }
        if input.auAudioUnit.deviceID == id { return }
        if (try? input.auAudioUnit.setDeviceID(id)) != nil { return }
        guard let au = input.audioUnit else { return }
        var copy = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &copy,
            size
        )
    }

    private func detachEngine(closeWriter: Bool) {
        clearEngineObserver()
        if let engine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            if engine.inputNode.isVoiceProcessingEnabled {
                try? engine.inputNode.setVoiceProcessingEnabled(false)
            }
            if engine.isRunning { engine.stop() }
            engine.disconnectNodeInput(engine.mainMixerNode)
            engine.reset()
        }
        self.engine = nil
        tapInstalled = false
        if closeWriter {
            writer?.finish()
            writer = nil
        }
    }

    private func teardownSession(keepFile: Bool) {
        endSleepAssertion()
        enableAppExit()
        if !keepFile, let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
        }
    }

    private func listenForConfigurationChanges(_ engine: AVAudioEngine) {
        clearEngineObserver()
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard (note.object as? AVAudioEngine) === self.engine else { return }
            self.recoverEngine(reason: "音频设备变化")
        }
    }

    private func clearEngineObserver() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
            self.engineObserver = nil
        }
    }

    private func beginSleepAssertion() {
        endSleepAssertion()
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "求索正在录课堂"
        )
    }

    private func endSleepAssertion() {
        if let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }

    private func disableAppExit() {
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("求索正在录音")
    }

    private func enableAppExit() {
        ProcessInfo.processInfo.enableSuddenTermination()
        ProcessInfo.processInfo.enableAutomaticTermination("求索正在录音")
    }
}

private final class Preroll: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var totalFrames: AVAudioFrameCount = 0
    private let maxFrames: AVAudioFrameCount = 96_000

    func push(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, let copy = Self.copy(buffer) else { return }
        lock.lock()
        buffers.append(copy)
        totalFrames += copy.frameLength
        while totalFrames > maxFrames, let first = buffers.first {
            totalFrames -= first.frameLength
            buffers.removeFirst()
        }
        lock.unlock()
    }

    func flush(into writer: RecordingWriter) {
        lock.lock()
        let pending = buffers
        buffers.removeAll()
        totalFrames = 0
        lock.unlock()
        for buffer in pending {
            writer.append(buffer)
        }
    }

    func clear() {
        lock.lock()
        buffers.removeAll()
        totalFrames = 0
        lock.unlock()
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dest = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        dest.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if buffer.format.isInterleaved {
            let count = frames * channels
            if let src = buffer.floatChannelData?[0], let dst = dest.floatChannelData?[0] {
                dst.update(from: src, count: count)
                return dest
            }
            if let src = buffer.int16ChannelData?[0], let dst = dest.int16ChannelData?[0] {
                dst.update(from: src, count: count)
                return dest
            }
        } else {
            if let src = buffer.floatChannelData, let dst = dest.floatChannelData {
                for c in 0..<channels {
                    dst[c].update(from: src[c], count: frames)
                }
                return dest
            }
            if let src = buffer.int16ChannelData, let dst = dest.int16ChannelData {
                for c in 0..<channels {
                    dst[c].update(from: src[c], count: frames)
                }
                return dest
            }
        }
        return nil
    }
}

/// CAF 48 kHz 16-bit mono PCM. Full-band source for dictation; AAC after a successful transcript.
private final class RecordingWriter: @unchecked Sendable {
    static let targetRate: Double = PCMConvert.targetRate

    private var file: AVAudioFile?
    private let convert = PCMConvert()
    private let lock = NSLock()
    private var closed = false
    private var framesWritten: AVAudioFramePosition = 0
    private var peak: Float = 0
    private var lastWriteError: String?
    private var consecutiveDrops = 0

    func snapshot() -> (frames: AVAudioFramePosition, error: String?, peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (framesWritten, lastWriteError, peak)
    }

    init(url: URL) throws {
        file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: Self.targetRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let file, buffer.frameLength > 0 else { return }
        guard let converted = convert.convert(buffer) else {
            consecutiveDrops += 1
            if consecutiveDrops >= 8 {
                lastWriteError = "麦克风数据转换失败，已连续丢掉 \(consecutiveDrops) 包。"
            }
            return
        }
        do {
            try file.write(from: converted)
            framesWritten += AVAudioFramePosition(converted.frameLength)
            let rms = PCMReader.rms(of: converted)
            if rms > peak { peak = rms }
            consecutiveDrops = 0
            lastWriteError = nil
        } catch {
            lastWriteError = error.localizedDescription
        }
    }

    func finish() {
        lock.lock()
        closed = true
        file = nil
        lock.unlock()
    }
}

public enum RecorderError: LocalizedError {
    case noMicrophone
    case startFailed
    case alreadyRecording
    case emptyFile
    case compressFailed

    public var errorDescription: String? {
        switch self {
        case .noMicrophone: return "需要麦克风权限才能录课堂音频。"
        case .startFailed: return "无法开始录音。"
        case .alreadyRecording: return "已经在录音。请先停止当前这一条。"
        case .emptyFile: return "录音计时在走，但麦克风数据没有写入文件。请再录一次。"
        case .compressFailed: return "音频压缩失败，原文件已保留。"
        }
    }
}

enum ISO8601 {
    static var fileNow: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
