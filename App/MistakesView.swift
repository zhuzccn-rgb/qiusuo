import SwiftUI
import AppKit
import LexiconCore
import LexiconInbox

struct MistakesView: View {
    @EnvironmentObject private var state: AppState

    private var filtered: [Mistake] { state.filteredMistakes }

    var body: some View {
        Group {
            if state.mistakes.isEmpty {
                PanePlaceholder(title: "还没有错题", systemImage: "xmark.seal")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: state.searchText)
            } else {
                List(filtered, id: \.id, selection: $state.selectedMistakeID) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.subject)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            if item.hasAnalysis {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(item.question).lineLimit(2)
                    }
                    .contextMenu {
                        Button("删除", role: .destructive) { state.delete(item) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        if let id = state.selectedMistakeID, filtered.contains(where: { $0.id == id }) { return }
        state.selectedMistakeID = filtered.first?.id
    }
}

struct MistakeDetailPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let item = ArchiveSearch.item(state.mistakes, id: state.selectedMistakeID) {
            MistakeDetail(item: item)
                .id(item.id)
        } else {
            PanePlaceholder(title: "选择一道错题", systemImage: "xmark.seal")
        }
    }
}

struct MistakeDetail: View {
    @EnvironmentObject private var state: AppState
    @State var item: Mistake

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("科目", selection: $item.subject) {
                        ForEach(SubjectPreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .frame(maxWidth: 180)
                    Spacer()
                    Button("保存") { state.save(item) }
                        .keyboardShortcut("s", modifiers: .command)
                    Button("总结") {
                        Task { await state.summarizeMistake(item) }
                    }
                    .disabled(state.busy)
                    Button("识别文字") {
                        Task { await state.recognizeMistakeText(item) }
                    }
                    .disabled(
                        state.busy
                            || item.imagePath.isEmpty
                            || !DocumentTextRecognizer.shouldFillEmptyNotes(item.analysis)
                    )
                    .help(
                        DocumentTextRecognizer.shouldFillEmptyNotes(item.analysis)
                            ? "识别写入空分析，已有手写不覆盖"
                            : "已有分析，不会覆盖"
                    )
                }
                labeled("题干") { TextEditor(text: $item.question).frame(minHeight: 80).scrollContentBackground(.hidden) }
                labeled("我的错解") { TextEditor(text: $item.wrongAnswer).frame(minHeight: 60).scrollContentBackground(.hidden) }
                labeled("正确答案") { TextEditor(text: $item.correctAnswer).frame(minHeight: 60).scrollContentBackground(.hidden) }
                labeled("标签") { TextField("函数, 极值", text: $item.tags) }
                if let url = item.imageURL, FileManager.default.fileExists(atPath: url.path),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                labeled("模型分析") {
                    Text(item.analysis.isEmpty ? "尚未生成分析" : item.analysis)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.mistakes) { _, _ in
            if let latest = state.mistakes.first(where: { $0.id == item.id }) { item = latest }
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
