import Foundation

/// iPad / AirDrop lecture files: keep the inbox path, copy anything else into recordings.
public enum LectureAudioImport: Sendable {
    public static let extensions: Set<String> = ["m4a", "mp3", "wav", "aac", "caf", "flac"]

    public static func isAudioFile(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func keepInPlace(source: URL, inboxRoot: URL, recordingsDirectory: URL) -> Bool {
        isInside(source, directory: inboxRoot) || isInside(source, directory: recordingsDirectory)
    }

    public static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        let stem = base.isEmpty ? "imported" : base
        var n = 0
        while n < 1000 {
            let name = n == 0
                ? (ext.isEmpty ? stem : "\(stem).\(ext)")
                : (ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)")
            let dest = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) {
                return dest
            }
            n += 1
        }
        let fallback = ext.isEmpty ? "\(stem)-\(UUID().uuidString)" : "\(stem)-\(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(fallback)
    }

    public static func isInside(_ file: URL, directory: URL) -> Bool {
        let files = [file.standardizedFileURL.path, file.resolvingSymlinksInPath().path]
        let dirs = [directory.standardizedFileURL.path, directory.resolvingSymlinksInPath().path]
        for path in files {
            for dir in dirs where !dir.isEmpty {
                if path == dir { return true }
                let prefix = dir.hasSuffix("/") ? dir : dir + "/"
                if path.hasPrefix(prefix) { return true }
            }
        }
        return false
    }
}
