import SwiftUI
import LexiconCore

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var settingsSection: SettingsSection = .inbox

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            // 状态条放列表底下那块空白，压在正文上会盖住字。
            listColumn
                .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            detailChrome
        }
        .searchable(text: $state.searchText, prompt: Text(searchPrompt))
        .searchSuggestions {
            ForEach(searchSuggestions, id: \.self) { text in
                Text(text).searchCompletion(text)
            }
        }
        .onChange(of: state.settings.llmModel) { _, _ in
            state.saveSettings()
        }
        .onChange(of: state.selected) { _, _ in
            state.searchText = ""
        }
    }

    /// 工具栏挂在详情栏上，系统才会把按钮画进最右栏。搜索用 `DefaultToolbarItem(.search)`
    /// 标明落在这一栏（苹果文档：searchable 仍要挂在 NavigationSplitView 上）。
    /// 项仍在这一处声明，按页 hidden，不要拆到各页去加。
    private var detailChrome: some View {
        detailColumn
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        let item = Homework(title: "新作业")
                        state.save(item)
                        state.selectedHomeworkID = item.id
                    } label: {
                        Label("新建作业", systemImage: "plus")
                    }
                    .help("新建作业")
                }
                .hidden(state.selected != .homework)
                ToolbarItem(placement: .principal) {
                    Button {
                        let item = Mistake(question: "新错题")
                        state.save(item)
                        state.selectedMistakeID = item.id
                    } label: {
                        Label("新建错题", systemImage: "plus")
                    }
                    .help("新建错题")
                }
                .hidden(state.selected != .mistakes)
                ToolbarItem(placement: .principal) {
                    Button {
                        state.exportLectures(state.filteredLectures)
                    } label: {
                        Label("导出列表", systemImage: "square.and.arrow.up")
                    }
                    .disabled(state.filteredLectures.isEmpty)
                    .help(lectureExportHelp)
                }
                .hidden(state.selected != .lectures)
                ToolbarItem(placement: .principal) {
                    Button {
                        Task { await state.reclassifyLecturesFromCalendar() }
                    } label: {
                        Label("按日历重新归类", systemImage: "calendar.badge.clock")
                    }
                    .disabled(state.busy || state.lectures.isEmpty)
                    .help("用 Mac 日历课表按时间匹配课名")
                }
                .hidden(state.selected != .lectures)
                ToolbarItem(placement: .principal) {
                    Button {
                        state.chooseAudioToImport()
                    } label: {
                        Label("导入录音", systemImage: "mic.badge.plus")
                    }
                    .help("自己选择一个音频文件导入。不会自动搬走「下载」或 AirDrop 里的文件")
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }
                .hidden(state.selected != .inbox)
                ToolbarItem(placement: .principal) {
                    Button {
                        state.refreshInbox()
                    } label: {
                        Label("刷新收件箱", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .hidden(state.selected != .inbox)
                ToolbarItem(placement: .principal) {
                    Button {
                        state.importAllInbox()
                    } label: {
                        Label("全部导入", systemImage: "tray.and.arrow.down")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(state.inbox.isEmpty)
                }
                .hidden(state.selected != .inbox)
                ToolbarItem(placement: .principal) {
                    Picker("模型", selection: $state.settings.llmModel) {
                        if !state.availableModels.contains(state.settings.llmModel) {
                            Text(state.settings.llmModel.isEmpty ? "未选择模型" : LLMModelChoice.toolbarLabel(state.settings.llmModel))
                                .tag(state.settings.llmModel)
                        }
                        ForEach(state.availableModels, id: \.self) { id in
                            Text(LLMModelChoice.toolbarLabel(id)).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 140, maxWidth: 240)
                    .help(state.settings.llmModel.isEmpty ? "当前推理模型" : state.settings.llmModel)
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        Task { await state.refreshModels() }
                    } label: {
                        Label("刷新模型", systemImage: "arrow.clockwise")
                    }
                    .help(state.modelsMessage.isEmpty ? "刷新模型列表" : state.modelsMessage)
                }
                if #available(macOS 26.0, *) {
                    DefaultToolbarItem(kind: .search, placement: .automatic)
                }
            }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(SidebarItem.allCases, selection: $state.selected) { item in
            Label {
                HStack(spacing: 6) {
                    Text(item.rawValue)
                    if item == .lectures, state.recorder.isRecording {
                        Circle()
                            .fill(state.recorder.isStalled ? Color.orange : Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
            } icon: {
                Image(systemName: item.icon)
            }
            .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("求索")
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    }

    @ViewBuilder
    private var listColumn: some View {
        switch state.selected {
        case .homework: HomeworkView()
        case .mistakes: MistakesView()
        case .lectures: RecordingsView()
        case .inbox: InboxView()
        case .settings:
            List(SettingsSection.allCases, selection: $settingsSection) { section in
                Text(section.title).tag(section)
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            switch state.selected {
            case .homework: HomeworkDetailPane()
            case .mistakes: MistakeDetailPane()
            case .lectures: LectureDetailPane()
            case .inbox: InboxDetailPane()
            case .settings: SettingsPane(section: settingsSection)
            }
        }
        .navigationTitle(state.selected.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lectureExportHelp: String {
        if !ArchiveSearch.query(state.searchText).isEmpty {
            return "导出搜索到的 \(state.filteredLectures.count) 条（可按标签搜）"
        }
        if state.lectureBrowse.isActive {
            return "导出当前日期和课程下的 \(state.filteredLectures.count) 条"
        }
        return "导出当前全部课堂笔记"
    }

    private var searchPrompt: String {
        switch state.selected {
        case .homework: return "搜索作业"
        case .mistakes: return "搜索错题"
        case .lectures: return "搜索录音"
        case .inbox: return "搜索收件箱"
        case .settings: return "搜索"
        }
    }

    private var searchSuggestions: [String] {
        switch state.selected {
        case .homework:
            return ArchiveSearch.suggestions(from: state.homework.map(\.subject), query: state.searchText)
        case .mistakes:
            return ArchiveSearch.suggestions(
                from: state.mistakes.map(\.subject) + state.mistakes.flatMap(\.tagList),
                query: state.searchText
            )
        case .lectures:
            return ArchiveSearch.suggestions(
                from: state.lectures.map(\.subject) + state.lectures.flatMap(\.tagList),
                query: state.searchText
            )
        case .inbox:
            return ArchiveSearch.suggestions(
                from: state.inbox.map(\.kindLabel) + state.inbox.map(\.url.lastPathComponent),
                query: state.searchText
            )
        case .settings:
            return []
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if showFooter {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if state.busy || state.speech.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private var footerText: String {
        if state.speech.isTranscribing, !state.speech.progressText.isEmpty {
            let title = state.lectureTitle(id: state.transcribingLectureID)
            if title.isEmpty { return state.speech.progressText }
            return "\(title) · \(state.speech.progressText)"
        }
        let msg = state.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg == "录音中" || msg.hasPrefix("录音中 ·") { return "" }
        return msg
    }

    private var showFooter: Bool {
        state.busy || state.speech.isTranscribing || !footerText.isEmpty
    }
}
