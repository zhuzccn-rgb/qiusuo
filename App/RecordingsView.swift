import SwiftUI
import AppKit
import LexiconCore
import LexiconLLM

struct RecordingsView: View {
    @EnvironmentObject private var state: AppState

    private var filtered: [Lecture] { state.filteredLectures }

    var body: some View {
        Group {
            if state.lectures.isEmpty {
                PanePlaceholder(title: L10n.text("还没有录音"), systemImage: "mic.square")
            } else {
                VStack(spacing: 0) {
                    lectureFilters
                    Divider()
                    if filtered.isEmpty {
                        if ArchiveSearch.query(state.searchText).isEmpty {
                            ContentUnavailableView(
                                L10n.text("没有符合条件的录音"),
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text(L10n.text("调整日期区间或课程名称。"))
                            )
                        } else {
                            ContentUnavailableView.search(text: state.searchText)
                        }
                    } else {
                        List(selection: $state.selectedLectureID) {
                            ForEach(state.filteredLectureGroups, id: \.course) { group in
                                Section(group.course) {
                                    ForEach(group.lectures) { item in
                                        lectureRow(item)
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            recordingBar
        }
        .onAppear { ensureSelection() }
        .onChange(of: state.focusLectureID) { _, id in
            if let id { state.selectedLectureID = id }
        }
        .onChange(of: state.lectureListEpoch) { _, _ in
            ensureSelection()
        }
        .onChange(of: state.searchText) { _, _ in
            ensureSelection()
        }
        .onChange(of: state.lectureBrowse) { _, _ in
            ensureSelection()
        }
    }

    @ViewBuilder
    private var recordingBar: some View {
        VStack(spacing: 6) {
            if state.recorder.isRecording {
                Button(L10n.text("停止并保存"), role: .destructive) {
                    state.stopRecordingAndSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
                Text(recordingStatusLine)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(state.recorder.isStalled ? .orange : .secondary)
                if let err = state.recorder.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } else {
                Button {
                    Task { await state.startRecording() }
                } label: {
                    Label(L10n.text("开始录音"), systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(state.speech.isTranscribing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var recordingStatusLine: String {
        let written = timeString(state.recorder.capturedSeconds)
        let device = state.recorder.inputDeviceName.isEmpty ? L10n.text("麦克风") : state.recorder.inputDeviceName
        if state.recorder.isStalled {
            return L10n.text("写入已停止 · \(written) · \(device)")
        }
        return L10n.text("已写入 \(written) · \(device)")
    }

    private var lectureFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(L10n.text("从"), selection: rangeStart, displayedComponents: .date)
                .help(L10n.text("录音日期的起始日，含当天"))
            DatePicker(L10n.text("到"), selection: rangeEnd, displayedComponents: .date)
                .help(L10n.text("录音日期的结束日，含当天"))
            HStack(spacing: 8) {
                Picker(L10n.text("课程"), selection: courseSelection) {
                    Text(L10n.text("全部课程")).tag("")
                    ForEach(courseOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                Button(L10n.text("重置")) {
                    state.lectureBrowse = LectureBrowseFilter()
                }
                .disabled(!state.lectureBrowse.isActive)
            }
        }
        .controlSize(.small)
        .datePickerStyle(.field)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var courseOptions: [String] {
        var names = state.lectureCourseNames
        let selected = LectureBrowseFilter.normalized(state.lectureBrowse.course)
        if !selected.isEmpty, !names.contains(where: { $0.localizedCaseInsensitiveCompare(selected) == .orderedSame }) {
            names.append(selected)
        }
        return names
    }

    private var dateBounds: (start: Date, end: Date) {
        let calendar = Calendar.current
        var start = Date.distantFuture
        var end = Date.distantPast
        for lecture in state.lectures {
            let day = calendar.startOfDay(for: lecture.createdAt)
            if day < start { start = day }
            if day > end { end = day }
        }
        if start == Date.distantFuture {
            let today = calendar.startOfDay(for: Date())
            return (today, today)
        }
        return (start, end)
    }

    private var rangeStart: Binding<Date> {
        Binding(
            get: { state.lectureBrowse.start ?? dateBounds.start },
            set: { newValue in
                var filter = state.lectureBrowse
                filter.start = newValue
                state.lectureBrowse = filter
            }
        )
    }

    private var rangeEnd: Binding<Date> {
        Binding(
            get: { state.lectureBrowse.end ?? dateBounds.end },
            set: { newValue in
                var filter = state.lectureBrowse
                filter.end = newValue
                state.lectureBrowse = filter
            }
        )
    }

    private var courseSelection: Binding<String> {
        Binding(
            get: { state.lectureBrowse.course },
            set: { newValue in
                var filter = state.lectureBrowse
                filter.course = newValue
                state.lectureBrowse = filter
            }
        )
    }

    private func lectureRow(_ item: Lecture) -> some View {
        let title = rowTitle(item)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(Self.dayClock.string(from: item.createdAt))
                if item.subject.localizedCaseInsensitiveCompare(title) != .orderedSame {
                    Text(L10n.subject(item.subject))
                }
                Text(timeString(item.duration))
                if state.transcribingLectureID == item.id {
                    ProgressView()
                        .controlSize(.mini)
                }
                if item.hasTranscript { Image(systemName: "text.alignleft") }
                if item.hasSummary { Image(systemName: "sparkles") }
                if item.duration < 0.4 {
                    Label(L10n.text("文件无效"), systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                } else if state.missingLectureFiles.contains(item.id) {
                    Label(L10n.text("找不到文件"), systemImage: "questionmark.folder")
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if !item.tagList.isEmpty {
                Text(item.tagList.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button(L10n.text("导出")) { state.exportLecture(item) }
            Button(L10n.text("删除"), role: .destructive) { state.delete(item) }
        }
        .tag(item.id)
    }

    private func rowTitle(_ item: Lecture) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let name = item.fileURL?.deletingPathExtension().lastPathComponent, !name.isEmpty {
            return name
        }
        return L10n.text("未命名")
    }

    private static let dayClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func ensureSelection() {
        if let id = state.selectedLectureID, filtered.contains(where: { $0.id == id }) { return }
        state.selectedLectureID = filtered.first?.id
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct LectureDetailPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let item = ArchiveSearch.item(state.lectures, id: state.selectedLectureID) {
            LectureDetail(item: item)
                .id(item.id)
        } else {
            PanePlaceholder(title: L10n.text("选择一条录音"), systemImage: "mic.square")
        }
    }
}

struct LectureDetail: View {
    @EnvironmentObject private var state: AppState
    @State var item: Lecture
    @State private var pane: LecturePane = .transcript

    private var fileMissing: Bool {
        state.missingLectureFiles.contains(item.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(L10n.text("课名"), text: $item.title)
                .font(.title2)
                .textFieldStyle(.plain)
            HStack {
                Picker(L10n.text("科目"), selection: $item.subject) {
                    ForEach(SubjectPreset.allCases) { Text(L10n.lookup($0.rawValue)).tag($0.rawValue) }
                }
                .frame(maxWidth: 180)
                Spacer()
                Button(L10n.text("保存")) { state.save(item) }
                    .keyboardShortcut("s", modifiers: .command)
            }
            if item.duration < 0.4 {
                Label(L10n.text("这份录音没有可用音频，无法转写。需要重新录一次。"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else if fileMissing {
                Label(L10n.text("找不到录音文件。"), systemImage: "questionmark.folder")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            TextField(L10n.text("标签，逗号分隔"), text: $item.tags)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button(L10n.text("开始转写")) {
                    Task { await state.transcribe(item) }
                }
                .disabled(state.busy || state.speech.isTranscribing || state.recorder.isRecording || item.duration < 0.4 || fileMissing)
                .lectureGlass()
                Button(L10n.text("提炼要点")) {
                    Task { await state.summarizeLecture(item) }
                }
                .disabled(state.busy || !item.hasTranscript)
                .lectureGlass()
                Button(L10n.text("导出")) {
                    state.exportLecture(item)
                }
                .disabled(state.busy)
                .lectureGlass()
                if state.transcribingLectureID == item.id {
                    Button(L10n.text("停止转写"), role: .destructive) {
                        state.cancelTranscription()
                    }
                    .lectureGlass()
                }
                if OnDeviceLectureTags.isAvailable {
                    Button(L10n.text("本机标签")) {
                        Task { await state.suggestOnDeviceTags(item) }
                    }
                    .disabled(state.busy || !item.hasTranscript)
                    .help(L10n.text("只用稿子开头生成本机短标签，不改已经写好的要点"))
                    .lectureGlass()
                }
                Spacer(minLength: 16)
                if pane == .transcript, !item.transcript.isEmpty {
                    Button(L10n.text("复制")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.transcript, forType: .string)
                    }
                    .lectureGlass()
                }
            }
            if state.transcribingLectureID == item.id {
                Text(state.speech.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LectureBottomTabs(
                pane: $pane,
                transcript: item.transcript,
                summary: item.summary,
                lectureID: item.id,
                contentToken: state.lectureToken(item.id)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: state.lectureToken(item.id)) { _, _ in
            if let latest = state.lectures.first(where: { $0.id == item.id }) {
                item = latest
            }
        }
    }
}

private enum LecturePane: String, CaseIterable, Identifiable {
    case transcript = "转写"
    case summary = "要点"

    var id: String { rawValue }
}

private extension View {
    @ViewBuilder
    func lectureGlass() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self
        }
    }
}

/// macOS 的 SwiftUI `TabView` 不能把标签放到底部。底栏标签用系统 `NSTabView`。
private struct LectureBottomTabs: NSViewRepresentable {
    @Binding var pane: LecturePane
    var transcript: String
    var summary: String
    var lectureID: String
    var contentToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pane: $pane)
    }

    func makeNSView(context: Context) -> NSTabView {
        let tabs = NSTabView()
        tabs.tabViewType = .bottomTabsBezelBorder
        tabs.delegate = context.coordinator
        let transcriptItem = NSTabViewItem(identifier: LecturePane.transcript.rawValue)
        transcriptItem.label = L10n.lookup(LecturePane.transcript.rawValue)
        transcriptItem.view = context.coordinator.transcriptHost
        let summaryItem = NSTabViewItem(identifier: LecturePane.summary.rawValue)
        summaryItem.label = L10n.lookup(LecturePane.summary.rawValue)
        summaryItem.view = context.coordinator.summaryHost
        tabs.addTabViewItem(transcriptItem)
        tabs.addTabViewItem(summaryItem)
        context.coordinator.apply(
            transcript: transcript,
            summary: summary,
            lectureID: lectureID,
            contentToken: contentToken
        )
        return tabs
    }

    func updateNSView(_ tabs: NSTabView, context: Context) {
        context.coordinator.pane = $pane
        context.coordinator.apply(
            transcript: transcript,
            summary: summary,
            lectureID: lectureID,
            contentToken: contentToken
        )
        let identifier = pane.rawValue
        if (tabs.selectedTabViewItem?.identifier as? String) != identifier,
           let item = tabs.tabViewItems.first(where: { ($0.identifier as? String) == identifier }) {
            tabs.selectTabViewItem(item)
        }
    }

    final class Coordinator: NSObject, NSTabViewDelegate {
        var pane: Binding<LecturePane>
        let transcriptModel: LectureTextModel
        let summaryModel: LectureTextModel
        let transcriptHost: NSHostingView<AnyView>
        let summaryHost: NSHostingView<AnyView>
        private var shownToken: Int?
        private var shownLectureID: String?

        init(pane: Binding<LecturePane>) {
            self.pane = pane
            let transcriptModel = LectureTextModel()
            let summaryModel = LectureTextModel()
            self.transcriptModel = transcriptModel
            self.summaryModel = summaryModel
            transcriptHost = NSHostingView(rootView: AnyView(LectureTabTranscript(model: transcriptModel)))
            summaryHost = NSHostingView(rootView: AnyView(LectureTabSummary(model: summaryModel)))
            super.init()
        }

        func apply(transcript: String, summary: String, lectureID: String, contentToken: Int) {
            if shownToken == contentToken, shownLectureID == lectureID { return }
            shownToken = contentToken
            shownLectureID = lectureID
            transcriptModel.update(text: transcript, lectureID: lectureID)
            summaryModel.update(text: summary, lectureID: lectureID)
        }

        func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            guard let raw = tabViewItem?.identifier as? String,
                  let next = LecturePane(rawValue: raw),
                  pane.wrappedValue != next else { return }
            pane.wrappedValue = next
        }
    }
}

private final class LectureTextModel: ObservableObject {
    @Published var text = ""
    @Published var lectureID = ""

    func update(text: String, lectureID: String) {
        if self.lectureID != lectureID {
            self.lectureID = lectureID
        }
        if self.text != text {
            self.text = text
        }
    }
}

private struct LectureTabTranscript: View {
    @ObservedObject var model: LectureTextModel

    var body: some View {
        ScrollView {
            LectureTranscriptView(text: model.text)
                .equatable()
                .id(model.lectureID)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LectureTabSummary: View {
    @ObservedObject var model: LectureTextModel

    var body: some View {
        ScrollView {
            Group {
                if model.text.isEmpty {
                    Text(L10n.text("尚未生成要点"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownBlock(source: model.text)
                        .id(model.lectureID)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LectureTranscriptView: View, Equatable {
    let text: String

    var body: some View {
        if text.isEmpty {
            Text(L10n.text("尚未转写"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if SummaryHTML.containsMath(text) {
            MarkdownBlock(source: text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(LectureTranscriptLayout.chunks(text).enumerated()), id: \.offset) { _, chunk in
                    Text(verbatim: chunk)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
