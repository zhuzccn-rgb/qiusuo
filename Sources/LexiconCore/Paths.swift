import Foundation

public enum AppPaths: Sendable {
    /// Explicitly isolate demos/tests from the owner's archive and Downloads.
    private static var isolatedDataDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["QIUSUO_DATA_DIRECTORY"],
              path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static var supportDirectory: URL {
        if let override = isolatedDataDirectory {
            let dir = override.appendingPathComponent("Library", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = root.appendingPathComponent("Lexicon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var databaseFile: URL {
        supportDirectory.appendingPathComponent("archive.sqlite")
    }

    public static var recordingsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// AirDrop on macOS always writes here. Not configurable.
    public static var airDropDirectory: URL {
        if let override = isolatedDataDirectory {
            return override.appendingPathComponent("Downloads", isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    public static var defaultInboxURL: URL {
        airDropDirectory.appendingPathComponent("LexiconInbox", isDirectory: true)
    }

    public static func isLegacyCloudInbox(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return lowered.contains("onedrive") || lowered.contains("cloudstorage")
    }

    public static var summarizeDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("summarize", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func transcriptSidecar(lectureID: String) -> URL {
        summarizeDirectory.appendingPathComponent("\(lectureID).txt")
    }

    public static func ensureInboxLayout(at root: URL) {
        let folders = ["作业", "笔记", "录音", "错题", "课件", "每周导入", "每周总结"]
        for name in folders {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let readme = root.appendingPathComponent("放到这里.txt")
        guard !FileManager.default.fileExists(atPath: readme.path) else { return }
        let text = """
        求索收件箱 / Qiusuo Inbox
        将你有权使用的材料放入对应文件夹，再在应用里手动导入。
        Place materials you are authorized to use in the matching folder, then import them in the app.
        作业 / Homework · 笔记 / Notes · 录音 / Recordings · 错题 / Mistakes · 课件 / Slides
        录音、转写、AI 处理和对外分享可能需要不同的许可。
        Recording, transcription, AI processing, and sharing can require separate permissions.
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }
}
