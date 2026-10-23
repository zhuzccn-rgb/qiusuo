import Darwin
import Foundation
import LexiconCore

/// Classifies a file a caller has already decided to move. The app does not scan
/// Downloads or call this on its own.
public enum AirDropInbox: Sendable {
    public static func destination(for url: URL, inboxRoot: URL) -> URL {
        let folder: String
        if InboxWatcher.isArchive(url) {
            folder = "每周导入"
        } else if LectureAudioImport.isAudioFile(url) {
            folder = "录音"
        } else {
            folder = ""
        }
        let dir = folder.isEmpty
            ? inboxRoot
            : inboxRoot.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LectureAudioImport.uniqueDestination(for: url, in: dir)
    }

    public static func isAirDropped(_ url: URL) -> Bool {
        quarantineText(url)?.contains("sharingd") == true
    }

    /// Immediate children of the AirDrop folder that `sharingd` wrote.
    @discardableResult
    public static func adopt(
        from dropFolder: URL,
        into inbox: URL,
        shouldTake: ((URL) -> Bool)? = nil
    ) -> [URL] {
        let fm = FileManager.default
        let drop = dropFolder.resolvingSymlinksInPath()
        let root = inbox.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: drop.path) else { return [] }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        guard let items = try? fm.contentsOfDirectory(
            at: drop,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let take = shouldTake ?? isAirDropped
        var moved: [URL] = []
        for item in items {
            if item.lastPathComponent == "LexiconInbox" { continue }
            if item.pathExtension.lowercased() == "download" { continue }
            if LectureAudioImport.isInside(item, directory: root) { continue }
            if !take(item) { continue }
            let dest = destination(for: item, inboxRoot: root)
            if item.standardizedFileURL.path == dest.standardizedFileURL.path { continue }
            do {
                try fm.moveItem(at: item, to: dest)
                moved.append(dest)
            } catch {
                continue
            }
        }
        return moved
    }

    private static func quarantineText(_ url: URL) -> String? {
        let path = url.path
        var size = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        size = getxattr(path, "com.apple.quarantine", &buffer, Int(size), 0, 0)
        guard size > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(size)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
