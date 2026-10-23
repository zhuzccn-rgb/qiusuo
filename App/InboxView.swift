import SwiftUI
import QuickLookUI
import LexiconCore
import LexiconInbox

struct InboxView: View {
    @EnvironmentObject private var state: AppState

    private var filtered: [InboxItem] { state.filteredInbox }

    var body: some View {
        Group {
            if state.inbox.isEmpty {
                PanePlaceholder(title: "收件箱是空的", systemImage: "tray")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: state.searchText)
            } else {
                List(filtered, selection: $state.selectedInboxID) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(item.kindLabel) · \(item.modified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contextMenu {
                        Button("用访达显示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            state.refreshInbox()
            ensureSelection()
        }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        if let id = state.selectedInboxID, filtered.contains(where: { $0.id == id }) { return }
        state.selectedInboxID = filtered.first?.id
    }
}

struct InboxDetailPane: View {
    @EnvironmentObject private var state: AppState

    private var item: InboxItem? {
        ArchiveSearch.item(state.filteredInbox, id: state.selectedInboxID)
    }

    var body: some View {
        if state.inbox.isEmpty {
            emptyInbox
        } else if let item {
            VStack(alignment: .leading, spacing: 0) {
                header(item)
                Divider()
                QuickLookPreview(url: item.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .id(item.id)
        } else {
            PanePlaceholder(title: "选择一个文件", systemImage: "tray")
        }
    }

    @ViewBuilder
    private func header(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.url.lastPathComponent)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Text(item.kindLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Text(item.modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                actions(item)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func actions(_ item: InboxItem) -> some View {
        Button("用访达显示") {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
        switch item.kind {
        case .slides:
            Text("课件留在收件箱，不会自动发给模型")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .archive:
            Text("压缩包留在这里，需要时再手动处理")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .audio:
            Button("导入录音") { state.importInboxItem(item) }
                .buttonStyle(.borderedProminent)
        default:
            Button("导入") { state.importInboxItem(item) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyInbox: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text("收件箱是空的")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("把选好的材料放进设置里的收件箱，或点「导入录音」自己选文件。求索不会自动搬走「下载」或 AirDrop 里的文件。")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("导入录音…") {
                state.chooseAudioToImport()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("收件箱是空的。把材料放进收件箱，或手动导入录音")
    }
}

/// 系统 QuickLook 预览（和访达空格预览同一套），PDF、图片、音频都认。
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        // 收件箱里全是课堂录音，自动播放会直接外放。必须关掉。
        view.autostarts = false
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        guard (nsView.previewItem as? NSURL) as URL? != url else { return }
        nsView.previewItem = url as NSURL
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}
