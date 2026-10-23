import CoreServices
import Foundation
import LexiconCore

public struct InboxItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case homework
        case note
        case audio
        case mistakePhoto
        case slides
        case archive
        case other
    }

    public var id: String { url.path }
    public var url: URL
    public var kind: Kind
    public var modified: Date

    public init(url: URL, kind: Kind, modified: Date) {
        self.url = url
        self.kind = kind
        self.modified = modified
    }

    public var kindLabel: String {
        switch kind {
        case .homework: return "作业"
        case .note: return "笔记"
        case .audio: return "录音"
        case .mistakePhoto: return "错题"
        case .slides: return "课件"
        case .archive: return "待分类"
        case .other: return "其他"
        }
    }

    public func matchesSearch(_ query: String) -> Bool {
        ArchiveSearch.matches(query, [
            url.lastPathComponent,
            url.path,
            kind.rawValue,
            kindLabel
        ])
    }
}

/// FSEvents watcher — one kernel stream, no polling, almost zero RAM.
public final class InboxWatcher {
    public var onChange: (() -> Void)?
    private var stream: FSEventStreamRef?
    private var currentPath: String = ""
    private let queue = DispatchQueue(label: "app.lexicon.inbox", qos: .utility)
    private var debounce: DispatchWorkItem?

    public init() {}

    deinit { stop() }

    /// Watches the configured inbox only. Downloads and AirDrop are not included.
    public func start(path: String) {
        stop()
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let root = URL(fileURLWithPath: trimmed)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        currentPath = trimmed
        let watched = [trimmed]
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<InboxWatcher>.fromOpaque(info).takeUnretainedValue().scheduleNotify()
        }
        guard let created = FSEventStreamCreate(
            nil,
            cb,
            &context,
            watched as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    private func scheduleNotify() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    public func stop() {
        debounce?.cancel()
        debounce = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    public func scan(path: String) -> [InboxItem] {
        Self.scan(path: path)
    }

    /// 纯文件系统读取，可在后台线程调用。
    public static func scan(path: String) -> [InboxItem] {
        let root = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [InboxItem] = []
        items.reserveCapacity(32)
        let skipNames: Set<String> = ["放到这里.txt", ".DS_Store", "课程主页.md"]
        while let file = enumerator.nextObject() as? URL {
            if file.lastPathComponent.hasSuffix(".icloud") { continue }
            if file.lastPathComponent.hasPrefix("~$") { continue }
            guard let values = try? file.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true { continue }
            if skipNames.contains(file.lastPathComponent) { continue }
            if (values.fileSize ?? 0) == 0 { continue }
            let modified = values.contentModificationDate ?? Date()
            items.append(InboxItem(url: file, kind: kind(for: file, inboxRoot: root), modified: modified))
        }
        return items.sorted { $0.modified > $1.modified }
    }

    /// First folder under the inbox root (`课件/CS61A/lec.pdf` → `课件`).
    public static func inboxFolder(for url: URL, inboxRoot: URL) -> String? {
        let root = urlPathComponents(inboxRoot)
        let parts = urlPathComponents(url)
        guard parts.starts(with: root), parts.count > root.count else { return nil }
        return parts[root.count]
    }

    public static func kind(for url: URL, inboxRoot: URL) -> InboxItem.Kind {
        switch inboxFolder(for: url, inboxRoot: inboxRoot) {
        case "录音":
            return .audio
        case "错题":
            return .mistakePhoto
        case "笔记":
            return .note
        case "课件":
            return .slides
        case "作业":
            return .homework
        case "每周导入":
            return .archive
        case "每周总结":
            return .other
        default:
            break
        }
        if isArchive(url) {
            return .archive
        }
        let ext = url.pathExtension.lowercased()
        if ["m4a", "mp3", "wav", "aac", "caf", "flac"].contains(ext) {
            return .audio
        }
        if ["md", "txt", "markdown"].contains(ext) {
            return .note
        }
        if ["pdf", "png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return .homework
        }
        return .other
    }

    public static func isArchive(_ url: URL) -> Bool {
        ["zip", "7z", "rar"].contains(url.pathExtension.lowercased())
    }

    private static func urlPathComponents(_ url: URL) -> [String] {
        url.standardizedFileURL.pathComponents
    }
}
