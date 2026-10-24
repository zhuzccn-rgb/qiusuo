import SwiftUI
import AppKit
import PDFKit
import LexiconCore
import LexiconInbox

struct HomeworkView: View {
    @EnvironmentObject private var state: AppState

    private var filtered: [Homework] { state.filteredHomework }

    var body: some View {
        Group {
            if state.homework.isEmpty {
                PanePlaceholder(title: L10n.text("还没有作业"), systemImage: "doc.richtext")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: state.searchText)
            } else {
                List(filtered, id: \.id, selection: $state.selectedHomeworkID) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).lineLimit(1)
                        Text("\(L10n.subject(item.subject)) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contextMenu {
                        Button(L10n.text("删除"), role: .destructive) { state.delete(item) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        if let id = state.selectedHomeworkID, filtered.contains(where: { $0.id == id }) { return }
        state.selectedHomeworkID = filtered.first?.id
    }
}

struct HomeworkDetailPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let item = ArchiveSearch.item(state.homework, id: state.selectedHomeworkID) {
            HomeworkDetail(item: item)
                .id(item.id)
        } else {
            PanePlaceholder(title: L10n.text("选择一份作业"), systemImage: "doc.richtext")
        }
    }
}

struct HomeworkDetail: View {
    @EnvironmentObject private var state: AppState
    @State var item: Homework
    @State private var mistakeQuestion = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField(L10n.text("标题"), text: $item.title)
                    .font(.title2)
                    .textFieldStyle(.plain)
                HStack {
                    Picker(L10n.text("科目"), selection: $item.subject) {
                        ForEach(SubjectPreset.allCases) { s in
                            Text(L10n.lookup(s.rawValue)).tag(s.rawValue)
                        }
                    }
                    .frame(maxWidth: 180)
                    Spacer()
                    Button(L10n.text("保存")) { state.save(item) }
                        .keyboardShortcut("s", modifiers: .command)
                }
                FilePreview(path: item.filePath)
                HStack {
                    Text(L10n.text("备注"))
                        .font(.headline)
                    Spacer()
                    Button(L10n.text("识别文字")) {
                        Task { await state.recognizeHomeworkText(item) }
                    }
                    .disabled(
                        state.busy
                            || item.filePath.isEmpty
                            || !DocumentTextRecognizer.shouldFillEmptyNotes(item.notes)
                    )
                    .help(
                        DocumentTextRecognizer.shouldFillEmptyNotes(item.notes)
                            ? L10n.text("识别写入空备注，不改预览")
                            : L10n.text("已有备注，不会覆盖")
                    )
                }
                TextEditor(text: $item.notes)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                Divider()
                Text(L10n.text("登记错题")).font(.headline)
                TextField(L10n.text("题干摘要"), text: $mistakeQuestion)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.text("加入错题本")) {
                    let q = mistakeQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !q.isEmpty else { return }
                    let mistake = Mistake(homeworkId: item.id, subject: item.subject, question: q, imagePath: item.filePath)
                    state.save(mistake)
                    state.selectedMistakeID = mistake.id
                    mistakeQuestion = ""
                }
                .disabled(mistakeQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncFromStore() }
        .onChange(of: state.homework) { _, _ in syncFromStore() }
    }

    private func syncFromStore() {
        if let latest = state.homework.first(where: { $0.id == item.id }) {
            item = latest
        }
    }
}

struct FilePreview: View {
    let path: String

    var body: some View {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        Group {
            if path.isEmpty {
                Label(L10n.text("尚未关联文件"), systemImage: "doc")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            } else if !FileManager.default.fileExists(atPath: path) {
                Label(L10n.text("找不到文件：\(url.lastPathComponent)"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if ext == "pdf" {
                PDFKitView(url: url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack {
                    Image(systemName: "doc")
                    Text(url.lastPathComponent)
                    Spacer()
                    Button(L10n.text("用访达打开")) { NSWorkspace.shared.open(url) }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
