import Foundation
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LexiconCore
import LexiconSpeech
import LexiconLLM
import LexiconInbox
import LexiconCalendar

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var homework: [Homework] = []
    @Published var mistakes: [Mistake] = []
    @Published var lectures: [Lecture] = []
    @Published var inbox: [InboxItem] = []
    /// 搜索框和工具栏都在 ContentView 一处声明，页面切换时工具栏项不重建（否则顶栏会闪）。
    @Published var searchText: String = ""
    /// 课堂录音列表的日期区间和课程名称。空着表示不限。
    @Published var lectureBrowse = LectureBrowseFilter()
    /// 列表每行都 stat 一次文件会在重绘时打满系统调用，改成载入时算一遍。
    @Published private(set) var missingLectureFiles: Set<Lecture.ID> = []
    @Published var selected: SidebarItem = .homework
    @Published var selectedHomeworkID: Homework.ID?
    @Published var selectedMistakeID: Mistake.ID?
    @Published var selectedLectureID: Lecture.ID?
    @Published var selectedInboxID: InboxItem.ID?
    @Published var statusMessage: String = ""
    @Published var busy: Bool = false
    @Published var availableModels: [String] = []
    @Published var modelsMessage: String = ""
    @Published var focusLectureID: Lecture.ID?
    @Published private(set) var transcribingLectureID: Lecture.ID?

    let store: ArchiveStore
    let speech = SpeechEngine()
    let recorder = AudioRecorder()
    let llm = LLMClient()
    let calendar = CalendarMatcher()
    private let watcher = InboxWatcher()
    private var cancellables = Set<AnyCancellable>()
    private var hourlyPrompt: Timer?
    private var pausePromptUp = false
    private var resumeRecordingAfterWake = false
    private var wakeResumePromptUp = false
    private var powerObservers: [NSObjectProtocol] = []
    private var lastPartialUIAt = Date.distantPast
    private var republishPending = false
    private var recorderStateKey = ""
    private var inboxScanSeq = 0
    /// Bumps when the lecture array actually changes. Recorder ticks do not.
    private var lecturesEpoch = 0
    private var lectureTokens: [Lecture.ID: Int] = [:]
    private var lectureFilterCacheKey: LectureFilterCacheKey?
    private var lectureFilterCache: [Lecture] = []
    private var lectureGroupCache: [LectureCourseGroup] = []
    private var lectureCourseNamesEpoch = -1
    private var lectureCourseNamesCache: [String] = []

    init() {
        do {
            store = try ArchiveStore()
            settings = try store.loadSettings()
        } catch {
            fatalError(L10n.text("无法打开数据库：\(error.localizedDescription)"))
        }
        if AppPaths.isLegacyCloudInbox(settings.inboxPath) {
            let dest = AppPaths.defaultInboxURL
            AppPaths.ensureInboxLayout(at: dest)
            settings.inboxPath = dest.path
            try? store.saveSettings(settings)
        }
        AppPaths.ensureInboxLayout(at: URL(fileURLWithPath: settings.inboxPath))
        recorder.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.recorder.needsAutoSave, self.recorder.isRecording {
                    self.stopRecordingAndSave()
                }
                self.republishRecorder()
            }
            .store(in: &cancellables)
        speech.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.coalesceRepublish() }
            .store(in: &cancellables)
        calendar.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        reload()
        store.backfillLectureFTS()
        adoptOrphanRecordings()
        adoptSidecarTranscripts()
        detachSlidesImportedAsHomework()
        startWatcher()
        watchPowerEvents()
        backfillLectureTagsIfNeeded()
        Task { await classifyUnmatchedLectures() }
    }

    func persistRecordingOnExit() {
        if recorder.isRecording {
            stopRecordingAndSave()
        }
    }

    /// 录音一秒要动好几个 @Published，逐个转发会把整个界面每秒判脏十来次。
    /// 开录/停录/卡写/报错立刻刷，秒表和转写进度按 0.4 秒合并。
    private func republishRecorder() {
        let key = "\(recorder.isRecording)|\(recorder.isStalled)|\(recorder.lastError ?? "")"
        if key != recorderStateKey {
            recorderStateKey = key
            republishPending = false
            objectWillChange.send()
            return
        }
        coalesceRepublish()
    }

    var filteredHomework: [Homework] {
        ArchiveSearch.apply(homework, query: searchText) { $0.matchesSearch(searchText) }
    }

    var filteredMistakes: [Mistake] {
        ArchiveSearch.apply(mistakes, query: searchText) { $0.matchesSearch(searchText) }
    }

    var filteredLectures: [Lecture] {
        // The lectures export item stays in the toolbar on every page. Don't run FTS
        // for a homework or mistake query.
        let query = selected == .lectures ? searchText : ""
        let key = LectureFilterCacheKey(epoch: lecturesEpoch, search: query, filter: lectureBrowse)
        if lectureFilterCacheKey == key {
            return lectureFilterCache
        }
        let ftsIDs = ArchiveSearch.query(query).isEmpty ? nil : lectureIDsMatching(query)
        let searched = ArchiveSearch.applyLectures(lectures, query: query, ftsIDs: ftsIDs)
        let value = ArchiveSearch.applyBrowseFilter(searched, filter: lectureBrowse)
        lectureFilterCacheKey = key
        lectureFilterCache = value
        lectureGroupCache = ArchiveSearch.groupByCourse(value)
        return value
    }

    var filteredLectureGroups: [LectureCourseGroup] {
        _ = filteredLectures
        return lectureGroupCache
    }

    var lectureCourseNames: [String] {
        if lectureCourseNamesEpoch == lecturesEpoch {
            return lectureCourseNamesCache
        }
        let names = ArchiveSearch.courseNames(in: lectures)
        lectureCourseNamesEpoch = lecturesEpoch
        lectureCourseNamesCache = names
        return names
    }

    var lectureListEpoch: Int { lecturesEpoch }

    func lectureToken(_ id: Lecture.ID) -> Int {
        lectureTokens[id] ?? 0
    }

    var filteredInbox: [InboxItem] {
        ArchiveSearch.apply(inbox, query: searchText) { $0.matchesSearch(searchText) }
    }

    private struct LectureFilterCacheKey: Equatable {
        var epoch: Int
        var search: String
        var filter: LectureBrowseFilter
    }

    /// Compare once per reload, not on every recorder tick. Unchanged rows keep their token
    /// so an open editor does not get its unsaved title replaced. Body text is compared by
    /// byte count except for the lecture currently open, which is compared in full so a
    /// same-length edit still refreshes.
    private func replaceLectures(_ next: [Lecture]) {
        var oldStamps: [Lecture.ID: LectureStamp] = [:]
        oldStamps.reserveCapacity(lectures.count)
        var previousSelected: Lecture?
        for lecture in lectures {
            oldStamps[lecture.id] = Self.stamp(lecture)
            if lecture.id == selectedLectureID {
                previousSelected = lecture
            }
        }
        var seen = Set<Lecture.ID>()
        seen.reserveCapacity(next.count)
        for lecture in next {
            seen.insert(lecture.id)
            let changed: Bool
            if lecture.id == selectedLectureID {
                changed = previousSelected != lecture
            } else {
                changed = oldStamps[lecture.id] != Self.stamp(lecture)
            }
            if changed {
                lectureTokens[lecture.id, default: 0] += 1
            }
        }
        for id in lectureTokens.keys where !seen.contains(id) {
            lectureTokens.removeValue(forKey: id)
        }
        lectures = next
        lecturesEpoch += 1
    }

    private struct LectureStamp: Equatable {
        var title: String
        var subject: String
        var tags: String
        var filePath: String
        var calendarEventId: String
        var duration: TimeInterval
        var createdAt: TimeInterval
        var transcriptBytes: Int
        var summaryBytes: Int
    }

    private static func stamp(_ lecture: Lecture) -> LectureStamp {
        LectureStamp(
            title: lecture.title,
            subject: lecture.subject,
            tags: lecture.tags,
            filePath: lecture.filePath,
            calendarEventId: lecture.calendarEventId,
            duration: lecture.duration,
            createdAt: lecture.createdAt.timeIntervalSince1970,
            transcriptBytes: lecture.transcript.utf8.count,
            summaryBytes: lecture.summary.utf8.count
        )
    }

    private static func missingFiles(in lectures: [Lecture]) -> Set<Lecture.ID> {
        var missing: Set<Lecture.ID> = []
        for lecture in lectures {
            guard let url = lecture.fileURL else { continue }
            if !FileManager.default.fileExists(atPath: url.path) {
                missing.insert(lecture.id)
            }
        }
        return missing
    }

    private func coalesceRepublish() {
        guard !republishPending else { return }
        republishPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.republishPending = false
            self.objectWillChange.send()
        }
    }

    func reload() {
        do {
            homework = try store.allHomework()
            mistakes = try store.allMistakes()
            replaceLectures(try store.allLectures())
            missingLectureFiles = Self.missingFiles(in: lectures)
        } catch {
            statusMessage = L10n.text("读取档案失败：\(error.localizedDescription)")
        }
        refreshInbox()
    }

    /// Slides stay in the inbox. Summaries do not read or send them.
    private func detachSlidesImportedAsHomework() {
        let root = URL(fileURLWithPath: settings.inboxPath)
        let misplaced = homework.filter {
            InboxWatcher.inboxFolder(for: URL(fileURLWithPath: $0.filePath), inboxRoot: root) == "课件"
        }
        guard !misplaced.isEmpty else { return }
        var removed = 0
        for item in misplaced {
            if mistakes.contains(where: { $0.homeworkId == item.id }) { continue }
            do {
                try store.deleteHomework(id: item.id)
                removed += 1
            } catch {
                continue
            }
        }
        guard removed > 0 else { return }
        reload()
        statusMessage = removed == 1
            ? L10n.text("已从作业里移出一份课件。课件留在收件箱，不会自动发给模型。")
            : L10n.text("已从作业里移出 \(removed) 份课件。课件留在收件箱，不会自动发给模型。")
    }

    /// Crash / force-quit can leave a CAF on disk with no SQLite row. Bring it back.
    private func adoptOrphanRecordings() {
        guard !recorder.isRecording else { return }
        let urls = LectureOrphans.candidateURLs(
            in: AppPaths.recordingsDirectory,
            knownPaths: lectures.map(\.filePath)
        )
        var added = 0
        for url in urls {
            if AudioFileIO.looksEmpty(url) { continue }
            let duration = PCMReader.duration(of: url)
            guard duration >= 1 else { continue }
            let created = LectureFileStamp.recordedAt(filePath: url.path)
                ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date)
                ?? Date()
            var item = Lecture(
                title: url.deletingPathExtension().lastPathComponent,
                filePath: url.path,
                duration: duration,
                createdAt: created
            )
            applyCalendarMatch(&item, overwrite: true)
            do {
                try store.upsert(item)
                added += 1
            } catch {
                continue
            }
        }
        if added > 0 {
            reload()
            statusMessage = added == 1
                ? L10n.text("发现一条上次未入库的录音，已加入列表。")
                : L10n.text("发现 \(added) 条上次未入库的录音，已加入列表。")
        }
    }

    func saveSettings() {
        do {
            try store.saveSettings(settings)
        } catch {
            statusMessage = L10n.text("设置未保存：\(error.localizedDescription)")
        }
        AppPaths.ensureInboxLayout(at: URL(fileURLWithPath: settings.inboxPath))
        startWatcher()
        refreshInbox()
    }

    func refreshModels() async {
        do {
            var ids = try await llm.listModels(settings: settings)
            if !settings.llmModel.isEmpty, !ids.contains(settings.llmModel) {
                ids.insert(settings.llmModel, at: 0)
            }
            availableModels = ids
            modelsMessage = ids.isEmpty ? L10n.text("该地址没有列出模型。") : L10n.text("\(ids.count) 个模型")
        } catch {
            availableModels = settings.llmModel.isEmpty ? [] : [settings.llmModel]
            modelsMessage = error.localizedDescription
        }
    }

    func startWatcher() {
        watcher.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshInbox()
            }
        }
        watcher.start(path: settings.inboxPath)
    }

    /// Scanning stays off the main thread. Only the configured inbox is listed.
    func refreshInbox() {
        let path = settings.inboxPath
        inboxScanSeq += 1
        let seq = inboxScanSeq
        Task.detached(priority: .utility) {
            let items = InboxWatcher.scan(path: path)
            await MainActor.run { [weak self] in
                guard let self, seq == self.inboxScanSeq else { return }
                self.inbox = items
            }
        }
    }

    func save(_ item: Homework) {
        persist { try store.upsert(item) }
    }

    func save(_ item: Mistake) {
        persist { try store.upsert(item) }
    }

    func save(_ item: Lecture) {
        persist { try store.upsert(item) }
    }

    func delete(_ item: Homework) {
        persist { try store.deleteHomework(id: item.id) }
    }

    func delete(_ item: Mistake) {
        persist { try store.deleteMistake(id: item.id) }
    }

    func delete(_ item: Lecture) {
        persist {
            if let url = item.fileURL {
                try? FileManager.default.removeItem(at: url)
                let leftover = url.deletingPathExtension()
                for ext in ["caf", "m4a", "wav"] {
                    let other = leftover.appendingPathExtension(ext)
                    if other.path != url.path {
                        try? FileManager.default.removeItem(at: other)
                    }
                }
            }
            try store.deleteLecture(id: item.id)
        }
    }

    private func persist(_ work: () throws -> Void) {
        do {
            try work()
            reload()
        } catch {
            if Database.isCorrupt(error) {
                statusMessage = L10n.text("保存失败：档案库曾损坏，已尝试修复。请再保存一次。录音文件还在。")
            } else {
                statusMessage = L10n.text("保存失败：\(error.localizedDescription)")
            }
        }
    }

    func importInboxItem(_ item: InboxItem) {
        if item.kind == .archive || InboxWatcher.isArchive(item.url) {
            statusMessage = L10n.text("压缩包不会自动导入。把要处理的文件留在收件箱，再手动导入。")
            return
        }
        if InboxWatcher.inboxFolder(for: item.url, inboxRoot: URL(fileURLWithPath: settings.inboxPath)) == "每周导入" {
            statusMessage = L10n.text("「每周导入」里的文件不会自动拆开或导入。")
            return
        }
        if InboxWatcher.inboxFolder(for: item.url, inboxRoot: URL(fileURLWithPath: settings.inboxPath)) == "每周总结" {
            statusMessage = L10n.text("「每周总结」不用导入。")
            return
        }
        switch item.kind {
        case .audio:
            importAudioAndReveal(item.url)
            return
        case .slides:
            statusMessage = L10n.text("课件留在收件箱。提炼要点不会读取课件，也不会把它发给模型。")
            return
        case .mistakePhoto:
            if (try? store.mistake(withImagePath: item.url.path)) != nil { return }
            save(Mistake(question: item.url.deletingPathExtension().lastPathComponent, imagePath: item.url.path))
        case .homework, .note, .other:
            if (try? store.homework(withFilePath: item.url.path)) != nil { return }
            var hw = Homework(title: item.url.deletingPathExtension().lastPathComponent, filePath: item.url.path)
            if item.kind == .note, let text = try? String(contentsOf: item.url, encoding: .utf8) {
                hw.notes = text
            }
            save(hw)
        case .archive:
            statusMessage = L10n.text("压缩包不会自动导入。把要处理的文件留在收件箱，再手动导入。")
            return
        }
        statusMessage = L10n.text("已导入 \(item.url.lastPathComponent)")
    }

    func importAllInbox() {
        var audioCount = 0
        var otherCount = 0
        for item in inbox {
            if item.kind == .slides || item.kind == .archive { continue }
            if InboxWatcher.inboxFolder(for: item.url, inboxRoot: URL(fileURLWithPath: settings.inboxPath)) == "每周导入" {
                continue
            }
            if InboxWatcher.inboxFolder(for: item.url, inboxRoot: URL(fileURLWithPath: settings.inboxPath)) == "每周总结" {
                continue
            }
            if item.kind == .audio {
                if case .imported = ingestAudio(from: item.url) {
                    audioCount += 1
                }
                continue
            }
            let homeworkCount = homework.count
            let mistakeCount = mistakes.count
            importInboxItem(item)
            if homework.count > homeworkCount || mistakes.count > mistakeCount {
                otherCount += 1
            }
        }
        reload()
        var parts: [String] = []
        if audioCount > 0 { parts.append(L10n.text("\(audioCount) 条录音")) }
        if otherCount > 0 { parts.append(L10n.text("\(otherCount) 项")) }
        statusMessage = parts.isEmpty ? L10n.text("没有新文件可导入。") : L10n.text("已导入 ") + parts.joined(separator: "、")
    }

    func chooseAudioToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = L10n.text("导入录音")
        panel.prompt = L10n.text("导入")
        panel.allowedContentTypes = Self.audioContentTypes
        let inboxAudio = URL(fileURLWithPath: settings.inboxPath).appendingPathComponent("录音", isDirectory: true)
        if FileManager.default.fileExists(atPath: inboxAudio.path) {
            panel.directoryURL = inboxAudio
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importAudioFiles(panel.urls, reveal: true)
    }

    func importAudioAndReveal(_ url: URL) {
        importAudioFiles([url], reveal: true)
    }

    func importAudioFiles(_ urls: [URL], reveal: Bool) {
        var imported: [Lecture] = []
        var duplicates = 0
        var failures: [String] = []
        for url in urls {
            switch ingestAudio(from: url) {
            case .imported(let lecture):
                imported.append(lecture)
            case .duplicate:
                duplicates += 1
            case .empty:
                failures.append(L10n.text("「\(url.lastPathComponent)」还是空的或没下完"))
            case .notAudio:
                failures.append(L10n.text("「\(url.lastPathComponent)」不是录音"))
            case .failed(let message):
                failures.append("「\(url.lastPathComponent)」\(message)")
            }
        }
        reload()
        if let last = imported.last, reveal {
            focusLectureID = last.id
            selectedLectureID = last.id
            selected = .lectures
        }
        if imported.count == 1 {
            statusMessage = L10n.text("已导入录音 \(imported[0].title)")
        } else if imported.count > 1 {
            statusMessage = L10n.text("已导入 \(imported.count) 条录音")
        } else if duplicates > 0, failures.isEmpty {
            statusMessage = L10n.text("这些录音已经在列表里。")
        } else if let first = failures.first {
            statusMessage = first
        }
    }

    private enum AudioIngest {
        case imported(Lecture)
        case duplicate
        case empty
        case notAudio
        case failed(String)
    }

    private static let audioContentTypes: [UTType] = {
        var types: [UTType] = [.mpeg4Audio, .mp3, .wav]
        for ext in LectureAudioImport.extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }()

    /// Explicit import only. Files already in the inbox or archive stay put. Nothing is pulled from Downloads.
    private func ingestAudio(from url: URL) -> AudioIngest {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard LectureAudioImport.isAudioFile(url) else { return .notAudio }
        if AudioFileIO.looksEmpty(url) { return .empty }

        let inboxRoot = URL(fileURLWithPath: settings.inboxPath)
        let recordings = AppPaths.recordingsDirectory
        try? FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)

        let dest: URL
        if LectureAudioImport.keepInPlace(source: url, inboxRoot: inboxRoot, recordingsDirectory: recordings) {
            dest = url.standardizedFileURL
        } else {
            dest = LectureAudioImport.uniqueDestination(for: url, in: recordings)
        }
        let destPath = dest.standardizedFileURL.path
        if (try? store.lecture(withFilePath: destPath)) != nil
            || (try? store.lecture(withFilePath: dest.path)) != nil
            || (try? store.lecture(withFilePath: url.path)) != nil {
            return .duplicate
        }
        if destPath != url.standardizedFileURL.path {
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        let created = LectureFileStamp.recordedAt(filePath: dest.path)
            ?? LectureFileStamp.recordedAt(filePath: url.path)
            ?? (try? FileManager.default.attributesOfItem(atPath: dest.path)[.creationDate] as? Date)
            ?? Date()
        var lecture = Lecture(
            title: dest.deletingPathExtension().lastPathComponent,
            filePath: destPath,
            createdAt: created
        )
        lecture.duration = PCMReader.duration(of: dest)
        applyCalendarMatch(&lecture, overwrite: lecture.calendarEventId.isEmpty)
        do {
            try store.upsert(lecture)
            return .imported(lecture)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func confirmRecordingAuthorization() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.text("确认可以录这一段吗？")
        alert.informativeText = L10n.text("""
        每一次开始录音都会重新询问，只对这一段有效。
        如为课堂录音，请先取得授课教师书面许可，或确认适用的便利安排允许录这堂课；其他场景也请先取得所需许可。
        录音会保存其他人的声音。请顾及在场其他人的隐私，不要录他们不愿被记录的内容。
        取消不会申请麦克风权限，也不会打开麦克风。
        """)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("取消"))
        alert.addButton(withTitle: L10n.text("已获得授权，开始录音"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    func startRecording() async {
        if recorder.isRecording { return }
        if speech.isTranscribing {
            statusMessage = L10n.text("正在转写，请先停止再录音。")
            return
        }
        guard confirmRecordingAuthorization() else {
            recorder.unprime()
            statusMessage = L10n.text("已取消。没有申请麦克风，也没有开始录音。")
            return
        }
        guard await recorder.requestPermission() else {
            recorder.unprime()
            statusMessage = L10n.text("请在系统设置里允许麦克风。")
            return
        }
        do {
            _ = try recorder.start(voiceProcessing: false)
            selected = .lectures
            statusMessage = ""
            scheduleHourlyPausePrompt()
        } catch {
            recorder.unprime()
            statusMessage = error.localizedDescription
        }
    }

    func stopRecordingAndSave() {
        hourlyPrompt?.invalidate()
        hourlyPrompt = nil
        pausePromptUp = false
        guard recorder.isRecording else { return }
        defer { recorder.unprime() }
        let url: URL
        do {
            guard let stopped = try recorder.stop() else { return }
            url = stopped
        } catch {
            statusMessage = error.localizedDescription
            return
        }
        if recorder.droppedVoiceProcessing, settings.voiceProcessing {
            settings.voiceProcessing = false
            saveSettings()
        }
        let frames = recorder.framesWritten
        let warning: String
        if frames == 0 {
            warning = L10n.text("文件未写入音频数据，已保留供检查。")
        } else if recorder.capturedPeak < 0.0008 {
            warning = L10n.text("录音电平很低，请检查麦克风；原件已保留。")
        } else {
            warning = ""
        }
        let duration = max(PCMReader.duration(of: url), recorder.capturedSeconds)
        let started = LectureFileStamp.recordedAt(filePath: url.path) ?? Date()
        var item = Lecture(
            title: url.deletingPathExtension().lastPathComponent,
            filePath: url.path,
            duration: duration,
            createdAt: started
        )
        applyCalendarMatch(&item, overwrite: true)
        save(item)
        focusLectureID = item.id
        selectedLectureID = item.id
        selected = .lectures
        statusMessage = item.calendarEventId.isEmpty ? L10n.text("已保存录音（\(Self.clock(duration))）") : L10n.text("已保存并归到「\(item.title)」")
        if !warning.isEmpty { statusMessage += " " + warning }
    }

    private func scheduleHourlyPausePrompt() {
        hourlyPrompt?.invalidate()
        hourlyPrompt = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.askWhetherToPause() }
        }
        if let hourlyPrompt {
            RunLoop.main.add(hourlyPrompt, forMode: .common)
        }
    }

    private func askWhetherToPause() {
        // A healthy multi-hour lecture must not be interrupted. Return on the
        // first button used to stop the recording; 45s stall already auto-saves.
        guard recorder.isRecording, recorder.isStalled, !pausePromptUp else { return }
        pausePromptUp = true
        let written = Self.clock(recorder.capturedSeconds)
        let alert = NSAlert()
        alert.messageText = L10n.text("录音写入已停止")
        alert.informativeText = L10n.text("已写入 \(written)。要保存已经录到的部分吗？")
        alert.addButton(withTitle: L10n.text("继续等待恢复"))
        alert.addButton(withTitle: L10n.text("停止并保存"))
        alert.alertStyle = .warning
        let reply = alert.runModal()
        pausePromptUp = false
        if reply == .alertSecondButtonReturn {
            stopRecordingAndSave()
        }
    }

    private func watchPowerEvents() {
        let nc = NSWorkspace.shared.notificationCenter
        powerObservers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillSleepFromNotification()
        })
        powerObservers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidWakeFromNotification()
        })
    }

    /// `queue: .main` is the main thread, which is where MainActor runs. Must stay
    /// synchronous: sleep proceeds as soon as the notification returns.
    nonisolated private func handleWillSleepFromNotification() {
        MainActor.assumeIsolated {
            handleWillSleep()
        }
    }

    nonisolated private func handleDidWakeFromNotification() {
        MainActor.assumeIsolated {
            handleDidWake()
        }
    }

    private func handleWillSleep() {
        guard recorder.isRecording else { return }
        resumeRecordingAfterWake = true
        stopRecordingAndSave()
        statusMessage = L10n.text("合盖前已保存录音")
    }

    private func handleDidWake() {
        guard resumeRecordingAfterWake else { return }
        resumeRecordingAfterWake = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.askResumeRecording()
        }
    }

    private func askResumeRecording() {
        guard !recorder.isRecording, !speech.isTranscribing, !wakeResumePromptUp else { return }
        wakeResumePromptUp = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text("电脑刚醒来")
        alert.informativeText = L10n.text("合盖前的录音已经保存。要继续录下一段吗？")
        alert.addButton(withTitle: L10n.text("继续录音"))
        alert.addButton(withTitle: L10n.text("不用了"))
        let reply = alert.runModal()
        wakeResumePromptUp = false
        if reply == .alertFirstButtonReturn {
            Task { await startRecording() }
        }
    }

    func transcribe(_ lecture: Lecture) async {
        guard !recorder.isRecording else {
            statusMessage = L10n.text("请先停止录音再转写。")
            return
        }
        let current = lectures.first(where: { $0.id == lecture.id }) ?? lecture
        guard let url = current.fileURL else { return }
        if AudioFileIO.looksEmpty(url) {
            statusMessage = L10n.text("这条录音文件是空的，没法转写。请重新录这一段。")
            return
        }
        busy = true
        transcribingLectureID = current.id
        statusMessage = L10n.text("转写中…")
        defer {
            busy = false
            transcribingLectureID = nil
        }
        do {
            var copy = current
            copy.duration = max(PCMReader.duration(of: url), current.duration)
            copy.transcript = try await speech.transcribe(
                file: url,
                localeIdentifier: settings.speechLocale,
                onPartial: { [weak self] text, _ in
                    Task { @MainActor in
                        self?.applyPartialTranscript(id: current.id, text: text)
                    }
                }
            )
            try store.upsert(copy)
            store.checkpoint()
            reload()
            if copy.tags.isEmpty, let tags = await OnDeviceLectureTags.suggest(from: copy.transcript) {
                copy.tags = tags
                try store.upsert(copy)
                reload()
            }
            statusMessage = L10n.text("转写完成")
        } catch {
            statusMessage = AudioFileIO.message(for: error)
        }
    }

    private func applyPartialTranscript(id: Lecture.ID, text: String) {
        let sidecar = AppPaths.transcriptSidecar(lectureID: id)
        Task.detached {
            try? text.write(to: sidecar, atomically: true, encoding: .utf8)
        }
        // Live preview used to replace the whole lecture (and re-layout 3–5 万字 Text)
        // on every SpeechAnalyzer sentence. That froze the window, then the process died.
        guard Date().timeIntervalSince(lastPartialUIAt) >= 2 else { return }
        lastPartialUIAt = Date()
        guard let index = lectures.firstIndex(where: { $0.id == id }) else { return }
        guard lectures[index].transcript != text else { return }
        var copy = lectures[index]
        copy.transcript = text
        lectures[index] = copy
        lectureTokens[id, default: 0] += 1
        lecturesEpoch += 1
    }

    /// Crash during transcription can leave a sidecar longer than the last SQLite row.
    private func adoptSidecarTranscripts() {
        var changed = false
        for lecture in lectures {
            let sidecar = AppPaths.transcriptSidecar(lectureID: lecture.id)
            guard let text = try? String(contentsOf: sidecar, encoding: .utf8) else { continue }
            guard text.count > lecture.transcript.count + 20 else { continue }
            var copy = lecture
            copy.transcript = text
            do {
                try store.upsert(copy)
                changed = true
            } catch {
                continue
            }
        }
        if changed {
            store.checkpoint()
            reload()
        }
    }

    func lectureTitle(id: Lecture.ID?) -> String {
        guard let id, let item = lectures.first(where: { $0.id == id }) else { return "" }
        return item.title
    }

    func cancelTranscription() {
        guard speech.isTranscribing else { return }
        speech.cancel()
        statusMessage = L10n.text("正在停止转写…")
    }

    private func confirmExport(count: Int, includesTranscript: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.text("导出前请再确认一次")
        alert.informativeText = L10n.text("""
        这次只会保存本机文件，不会自动发给别人。请确认你有权制作这些文字副本。
        将写出 \(count) 个 Markdown 文件\(includesTranscript ? L10n.text("，里面包含转写文本") : "")。不会附带原始音频。
        如果之后对外分享，请另外确认传播许可。
        """)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("取消"))
        alert.addButton(withTitle: L10n.text("继续导出"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    func exportLecture(_ item: Lecture) {
        guard confirmExport(count: 1, includesTranscript: item.hasTranscript) else {
            statusMessage = L10n.text("已取消导出。录音授权不等于可以分发。")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(sanitizedFileName(item.title)).md"
        panel.canCreateDirectories = true
        panel.title = L10n.text("导出课堂笔记")
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try writeMarkdown(item, to: dest)
            statusMessage = L10n.text("已导出 \(dest.lastPathComponent)。未附带原始音频。")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportLectures(_ items: [Lecture]) {
        guard !items.isEmpty else {
            statusMessage = L10n.text("没有可导出的录音。先在搜索框里按标签筛选。")
            return
        }
        guard confirmExport(count: items.count, includesTranscript: items.contains { $0.hasTranscript }) else {
            statusMessage = L10n.text("已取消导出。录音授权不等于可以分发。")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("导出到此文件夹")
        panel.message = L10n.text("将导出当前列表中的 \(items.count) 条笔记（Markdown）。不会附带原始音频。")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var count = 0
        for item in items {
            let name = uniqueName("\(sanitizedFileName(item.title)).md", in: folder)
            do {
                try writeMarkdown(item, to: folder.appendingPathComponent(name))
                count += 1
            } catch {
                statusMessage = error.localizedDescription
                return
            }
        }
        statusMessage = L10n.text("已导出 \(count) 条到 \(folder.lastPathComponent)。未附带原始音频。")
    }

    private func writeMarkdown(_ item: Lecture, to url: URL) throws {
        var lines: [String] = [
            "# \(item.title)",
            "",
            L10n.text("科目：\(item.subject)"),
            L10n.text("时长：\(Self.clock(item.duration))")
        ]
        if !item.tags.isEmpty {
            lines.append(L10n.text("标签：\(item.tags)"))
        }
        lines.append("")
        if item.hasSummary {
            lines.append(L10n.text("## 要点"))
            lines.append("")
            lines.append(item.summary)
            lines.append("")
        }
        if item.hasTranscript {
            lines.append(L10n.text("## 转写"))
            lines.append("")
            lines.append(item.transcript)
            lines.append("")
        }
        let text = lines.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func sanitizedFileName(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? L10n.text("录音") : String(cleaned.prefix(80))
    }

    private func uniqueName(_ name: String, in folder: URL) -> String {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        var candidate = name
        var i = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(i).\(ext)"
            i += 1
        }
        return candidate
    }

    private static let dayClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func lectureIDsMatching(_ query: String) -> [String]? {
        store.searchLectureIDs(matching: query)
    }

    func suggestOnDeviceTags(_ item: Lecture) async {
        guard OnDeviceLectureTags.isAvailable else { return }
        guard item.hasTranscript else {
            statusMessage = L10n.text("请先转写录音。")
            return
        }
        busy = true
        statusMessage = L10n.text("正在生成本机标签…")
        defer { busy = false }
        guard let tags = await OnDeviceLectureTags.suggest(from: item.transcript) else {
            statusMessage = L10n.text("本机标签不可用，仍可用提炼要点生成标签。")
            return
        }
        var copy = lectures.first(where: { $0.id == item.id }) ?? item
        copy.tags = LectureTags.merge(copy.tags, tags)
        do {
            try store.upsert(copy)
            reload()
            statusMessage = L10n.text("已写入本机标签")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func recognizeHomeworkText(_ item: Homework) async {
        await recognizeDocumentText(
            path: item.filePath,
            existing: item.notes,
            apply: { text in
                var copy = homework.first(where: { $0.id == item.id }) ?? item
                guard DocumentTextRecognizer.shouldFillEmptyNotes(copy.notes) else { return false }
                copy.notes = text
                try store.upsert(copy)
                return true
            }
        )
    }

    func recognizeMistakeText(_ item: Mistake) async {
        await recognizeDocumentText(
            path: item.imagePath,
            existing: item.analysis,
            apply: { text in
                var copy = mistakes.first(where: { $0.id == item.id }) ?? item
                guard DocumentTextRecognizer.shouldFillEmptyNotes(copy.analysis) else { return false }
                copy.analysis = text
                try store.upsert(copy)
                return true
            }
        )
    }

    private func recognizeDocumentText(
        path: String,
        existing: String,
        apply: (String) throws -> Bool
    ) async {
        guard DocumentTextRecognizer.shouldFillEmptyNotes(existing) else {
            statusMessage = L10n.text("已有备注，未覆盖")
            return
        }
        guard !path.isEmpty else {
            statusMessage = L10n.text("没有可识别的文件")
            return
        }
        let url = URL(fileURLWithPath: path)
        busy = true
        statusMessage = L10n.text("正在识别文字…")
        defer { busy = false }
        do {
            let text = try await DocumentTextRecognizer.recognize(url: url)
            if try apply(text) {
                reload()
                statusMessage = L10n.text("已写入识别文字")
            } else {
                statusMessage = L10n.text("已有备注，未覆盖")
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func confirmModelSend(messages: [ChatMessage], contents: String) -> Bool {
        let disclosure: LLMRequestDisclosure
        do {
            disclosure = try LLMRequestDisclosure.make(settings: settings, messages: messages)
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
        let alert = NSAlert()
        alert.messageText = L10n.text("确认把这些内容发给模型吗？")
        alert.informativeText = L10n.text("""
        发送内容：\(contents)

        接收地址：\(disclosure.destination)
        模型：\(disclosure.model)
        不会自动附带原始音频、本机文件路径或课件。

        请确认你有权将这些材料交给此服务处理。本机网关也可能继续转发内容。
        只有点「发送」才会发出请求。
        """)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("取消"))
        alert.addButton(withTitle: L10n.text("发送"))
        if alert.runModal() != .alertSecondButtonReturn {
            statusMessage = L10n.text("已取消，没有发送。")
            return false
        }
        return true
    }

    func summarizeMistake(_ item: Mistake) async {
        let messages = LLMPrompts.summarizeMistake(item)
        guard confirmModelSend(messages: messages, contents: L10n.text("科目、完整题目、你的错误答案及正确答案。")) else { return }
        busy = true
        statusMessage = L10n.text("正在请求模型…")
        defer { busy = false }
        do {
            var copy = item
            copy.analysis = try await llm.complete(settings: settings, messages: messages)
            try store.upsert(copy)
            reload()
            statusMessage = L10n.text("错题分析已写入")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func summarizeLecture(_ item: Lecture) async {
        guard item.hasTranscript else {
            statusMessage = L10n.text("请先转写录音。")
            return
        }
        let messages = LLMPrompts.summarizeLecture(
            title: item.title,
            subject: item.subject,
            recordedAt: Self.dayClock.string(from: item.createdAt),
            durationText: Self.clock(item.duration),
            transcript: item.transcript
        )
        guard confirmModelSend(messages: messages, contents: L10n.text("完整转写正文、课名、科目、录制时间及时长。")) else { return }
        busy = true
        statusMessage = L10n.text("正在请求模型…")
        defer { busy = false }
        do {
            var copy = item
            let raw = try await llm.complete(settings: settings, messages: messages)
            let split = LectureTags.splitSummary(raw)
            copy.summary = split.summary
            copy.tags = LectureTags.merge(split.tags, LectureTags.extractFromMarkdown(split.summary))
            try store.upsert(copy)
            reload()
            statusMessage = L10n.text("课堂要点已写入。录音和转写仍保留在本机。")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func pingLLM() async {
        busy = true
        defer { busy = false }
        statusMessage = await llm.ping(settings: settings)
    }

    func reclassifyLecturesFromCalendar() async {
        busy = true
        defer { busy = false }
        guard await ensureCalendarAccess() else { return }
        var count = 0
        for lecture in lectures {
            var copy = lecture
            if applyCalendarMatch(&copy, overwrite: true) {
                try? store.upsert(copy)
                count += 1
            }
        }
        reload()
        statusMessage = count == 0 ? L10n.text("日历里没有和录音时间重叠的课。") : L10n.text("已按课表归类 \(count) 条录音")
    }

    func requestCalendarAccess() async {
        guard await ensureCalendarAccess() else { return }
        await classifyUnmatchedLectures()
    }

    private func classifyUnmatchedLectures() async {
        calendar.refreshStatus()
        guard calendar.isAuthorized else { return }
        var changed = false
        for lecture in lectures where lecture.calendarEventId.isEmpty {
            var copy = lecture
            if applyCalendarMatch(&copy, overwrite: copy.calendarEventId.isEmpty) {
                try? store.upsert(copy)
                changed = true
            }
        }
        if changed { reload() }
    }

    @discardableResult
    private func ensureCalendarAccess() async -> Bool {
        calendar.refreshStatus()
        if calendar.isAuthorized { return true }
        let granted = await calendar.requestAccess()
        if !granted {
            statusMessage = calendar.accessHint
        }
        return granted
    }

    @discardableResult
    private func applyCalendarMatch(_ lecture: inout Lecture, overwrite: Bool) -> Bool {
        if !overwrite, !lecture.calendarEventId.isEmpty { return false }
        let excluded = Set(
            settings.calendarExcludedIds
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let guesses = LectureFileStamp.recordingGuesses(
            filePath: lecture.filePath,
            duration: lecture.duration,
            fallback: lecture.createdAt
        )
        let placeHint: String
        if LectureFileStamp.parse(lecture.filePath) != nil {
            placeHint = ""
        } else {
            placeHint = URL(fileURLWithPath: lecture.filePath).deletingPathExtension().lastPathComponent
        }
        var changed = false
        if let inferred = guesses.first?.start, abs(lecture.createdAt.timeIntervalSince(inferred)) > 1 {
            lecture.createdAt = inferred
            changed = true
        }
        guard let match = calendar.match(
            intervals: guesses,
            excludedCalendarIds: excluded,
            placeHint: placeHint
        ) else {
            return changed
        }
        lecture.createdAt = match.alignedStart
        lecture.calendarEventId = match.eventId
        if !match.title.isEmpty {
            lecture.title = match.title
        }
        if let subject = match.subject {
            lecture.subject = subject
        }
        return true
    }

    private func backfillLectureTagsIfNeeded() {
        var changed = false
        for lecture in lectures where lecture.tags.isEmpty && lecture.hasSummary {
            var copy = lecture
            let split = LectureTags.splitSummary(copy.summary)
            copy.summary = split.summary
            copy.tags = LectureTags.merge(split.tags, LectureTags.extractFromMarkdown(copy.summary))
            if copy.tags != lecture.tags || copy.summary != lecture.summary {
                try? store.upsert(copy)
                changed = true
            }
        }
        if changed { reload() }
    }
}

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case homework = "作业"
    case mistakes = "错题本"
    case lectures = "课堂录音"
    case inbox = "收件箱"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .homework: return "doc.richtext"
        case .mistakes: return "xmark.seal"
        case .lectures: return "mic.square"
        case .inbox: return "tray.and.arrow.down"
        case .settings: return "gearshape"
        }
    }

    /// 有「列表 + 详情」的页走系统三栏；设置是整页，走两栏。
    /// 不要用 `.inspector` 代替第三栏：检查器自带深色材质，工具栏会从中间断开。
    var hasListColumn: Bool {
        switch self {
        case .homework, .mistakes, .lectures, .inbox: return true
        case .settings: return false
        }
    }
}
