import SwiftUI
import AppKit
import LexiconCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case inbox
    case model
    case speech
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return L10n.text("收件箱")
        case .model: return L10n.text("远程模型")
        case .speech: return L10n.text("语音识别")
        case .calendar: return L10n.text("课表日历")
        }
    }
}

struct SettingsPane: View {
    @EnvironmentObject private var state: AppState
    var section: SettingsSection? = nil
    @State private var pingResult = ""

    var body: some View {
        Form {
            if let section {
                sectionView(section)
            } else {
                inboxSection
                modelSection
                speechSection
                calendarSection
            }
            Section {
                Button(L10n.text("保存设置")) { state.saveSettings() }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.calendar.refreshStatus() }
        .onDisappear { state.saveSettings() }
    }

    @ViewBuilder
    private func sectionView(_ section: SettingsSection) -> some View {
        switch section {
        case .inbox: inboxSection
        case .model: modelSection
        case .speech: speechSection
        case .calendar: calendarSection
        }
    }

    private var inboxSection: some View {
        Section(L10n.text("收件箱")) {
                LabeledContent(L10n.text("文件夹")) {
                    HStack(spacing: 8) {
                        Text(state.settings.inboxPath.isEmpty ? L10n.text("未选择") : state.settings.inboxPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help(state.settings.inboxPath)
                        Button(L10n.text("选择…")) { pickFolder() }
                    }
                }
                Text(L10n.text("把要处理的文件放进这个文件夹，或在收件箱里手动导入。求索只查看这里，不会监视「下载」，也不会自动搬走 AirDrop 来的文件。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

    }

    private var modelSection: some View {
        Section(L10n.text("远程模型")) {
                Picker(L10n.text("接口预设"), selection: $state.settings.llmPreset) {
                    ForEach(LLMPreset.allCases) { preset in
                        Text(L10n.lookup(preset.rawValue)).tag(preset)
                    }
                }
                .onChange(of: state.settings.llmPreset) { _, preset in
                    applyPreset(preset)
                }
                TextField("Base URL", text: $state.settings.llmBaseURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker(L10n.text("模型"), selection: $state.settings.llmModel) {
                        if !state.availableModels.contains(state.settings.llmModel) {
                            Text(state.settings.llmModel.isEmpty ? L10n.text("未选择") : LLMModelChoice.toolbarLabel(state.settings.llmModel))
                                .tag(state.settings.llmModel)
                        }
                        ForEach(state.availableModels, id: \.self) { id in
                            Text(LLMModelChoice.toolbarLabel(id)).tag(id)
                        }
                    }
                    Button {
                        Task { await state.refreshModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.text("刷新模型列表"))
                }
                if !state.modelsMessage.isEmpty {
                    Text(state.modelsMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField(L10n.text("自定义模型名"), text: $state.settings.llmModel)
                    .textFieldStyle(.roundedBorder)
                SecureField(L10n.text("API Key（仅本次运行）"), text: $state.settings.llmAPIKey)
                Text(L10n.text("预设会把地址改成本机 127.0.0.1。刷新模型列表和测试连接只会访问当前填写的地址，而且要点了才发。除 localhost、127.0.0.1、::1 外必须使用 https。不要把用户名或密码写进网址。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("测试连接")) {
                        Task {
                            await state.refreshModels()
                            await state.pingLLM()
                            pingResult = state.statusMessage
                        }
                    }
                    .disabled(state.busy)
                    Text(pingResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

    }

    private var speechSection: some View {
        Section(L10n.text("语音识别")) {
                Picker(L10n.text("识别语言"), selection: $state.settings.speechLocale) {
                    Text(L10n.text("英语")).tag("en-US")
                    Text(L10n.text("中文（普通话）")).tag("zh-CN")
                    Text(L10n.text("粤语")).tag("zh-HK")
                }
                Text(L10n.text("录音保留麦克风原始输入，不额外放大音量或开启通话人声处理。本机转写需要系统支持所选语言，首次可能下载语言资源。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

    }

    private var calendarSection: some View {
        Section(L10n.text("课表日历")) {
                LabeledContent(L10n.text("权限")) {
                    if state.calendar.isAuthorized {
                        Text(L10n.text("已允许"))
                            .foregroundStyle(.secondary)
                    } else {
                        Button(L10n.text("允许读取日历")) {
                            Task { await state.requestCalendarAccess() }
                        }
                    }
                }
                if state.calendar.isAuthorized {
                    ForEach(state.calendar.calendars) { calendar in
                        Toggle(calendar.title, isOn: calendarIncluded(calendar.id))
                    }
                    Text(L10n.text("关闭某个日历后，归类时会忽略它（例如生日、节假日）。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.calendar.accessHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func applyPreset(_ preset: LLMPreset) {
        state.settings.llmBaseURL = preset.defaultBaseURL
        if let model = preset.defaultModel {
            state.settings.llmModel = model
        } else if preset == .ollama && (state.settings.llmModel == "local" || state.settings.llmModel.hasPrefix("openclaw") || state.settings.llmModel == "hermes-agent") {
            state.settings.llmModel = "qwen2.5:7b"
        }
        state.saveSettings()
    }

    private func calendarIncluded(_ id: String) -> Binding<Bool> {
        Binding(
            get: {
                !state.settings.calendarExcludedIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(id)
            },
            set: { included in
                var ids = Set(
                    state.settings.calendarExcludedIds
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
                if included {
                    ids.remove(id)
                } else {
                    ids.insert(id)
                }
                state.settings.calendarExcludedIds = ids.sorted().joined(separator: ",")
                state.saveSettings()
            }
        )
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("用作收件箱")
        panel.directoryURL = URL(fileURLWithPath: state.settings.inboxPath.isEmpty
            ? AppPaths.defaultInboxURL.path
            : state.settings.inboxPath)
        if panel.runModal() == .OK, let url = panel.url {
            state.settings.inboxPath = url.path
            state.saveSettings()
        }
    }
}
