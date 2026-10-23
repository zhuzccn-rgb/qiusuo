import Foundation

/// How a recording's time window was inferred. Matching prefers filename start,
/// then “file created when it was saved”, and only treats creation as the start
/// when that start actually lands on a class.
public enum RecordingTimeAnchor: Sendable, Equatable {
    case filenameStart
    /// Voice Memo / m4a `mvhd` time when Finder birth is a later AirDrop copy.
    case mediaStart
    case creationAsEnd
    case creationAsStart
}

public struct RecordingSpan: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var anchor: RecordingTimeAnchor

    public init(start: Date, end: Date, anchor: RecordingTimeAnchor) {
        self.start = start
        self.end = end
        self.anchor = anchor
    }
}

/// File names from `AudioRecorder` look like `20260902-151047`. Calendar matching
/// must use this stamp (when recording started), not when the user later taps save.
public enum LectureFileStamp: Sendable {
    public static let pattern = "yyyyMMdd-HHmmss"

    public static func parse(_ name: String) -> Date? {
        let stamp = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.date(from: stamp)
    }

    public static func recordedAt(filePath: String) -> Date? {
        if let stamped = parse(filePath) { return stamped }
        let finder = fileCreationDate(at: filePath)
        if let media = mediaCreationDate(at: filePath) {
            if let finder, finder.timeIntervalSince(media) > copyDelaySlack {
                return media
            }
            if finder == nil { return media }
        }
        return finder
    }

    /// Possible [start, end] windows for calendar matching.
    /// Filename stamps are the start. A Voice Memo / import named "Dwinelle Hall"
    /// usually has Finder creation ≈ when the file was closed, so also try that as the end.
    /// AirDrop 会把访达创建时间改成拷贝时刻：这时改用 m4a 里的 mvhd 开录时间。
    public static func recordingGuesses(
        filePath: String,
        duration: TimeInterval,
        fallback: Date
    ) -> [RecordingSpan] {
        let length = (duration.isFinite && duration > 30) ? duration : 90 * 60
        if let stamped = parse(filePath) {
            return [RecordingSpan(start: stamped, end: stamped.addingTimeInterval(length), anchor: .filenameStart)]
        }
        let finder = fileCreationDate(at: filePath) ?? fallback
        if let media = mediaCreationDate(at: filePath), finder.timeIntervalSince(media) > copyDelaySlack {
            return [
                RecordingSpan(start: media, end: media.addingTimeInterval(length), anchor: .mediaStart),
                RecordingSpan(start: media.addingTimeInterval(-length), end: media, anchor: .creationAsEnd)
            ]
        }
        return [
            RecordingSpan(start: finder.addingTimeInterval(-length), end: finder, anchor: .creationAsEnd),
            RecordingSpan(start: finder, end: finder.addingTimeInterval(length), anchor: .creationAsStart)
        ]
    }

    public static let copyDelaySlack: TimeInterval = 10 * 60

    /// MPEG-4 movie header (Voice Memos `creation_time`). Not Finder birth.
    public static func mediaCreationDate(at filePath: String) -> Date? {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        guard ext == "m4a" || ext == "mp4" || ext == "m4v" || ext == "mov" else { return nil }
        return mpeg4MovieHeaderDate(at: filePath)
    }

    public static func fileCreationDate(at filePath: String) -> Date? {
        let url = URL(fileURLWithPath: filePath)
        if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            return created
        }
        return try? FileManager.default.attributesOfItem(atPath: filePath)[.creationDate] as? Date
    }

    public static func applyCreationDate(_ date: Date, to filePath: String) {
        try? FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: filePath)
    }

    /// MPEG-4 / QuickTime epoch: 1904-01-01 UTC.
    public static let mpeg4Epoch = Date(timeIntervalSince1970: -2_082_844_800)

    private static func mpeg4MovieHeaderDate(at filePath: String) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filePath)) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        guard end >= 16 else { return nil }
        return mpeg4FindMvhd(handle, start: 0, end: end)
    }

    private static func mpeg4FindMvhd(_ handle: FileHandle, start: UInt64, end: UInt64) -> Date? {
        var offset = start
        while offset + 8 <= end {
            guard let header = mpeg4Read(handle, at: offset, count: 8), header.count == 8 else { return nil }
            var size = u32(header, 0)
            let type = String(bytes: header[4..<8], encoding: .ascii) ?? ""
            var headerLen: UInt64 = 8
            if size == 1 {
                guard let wide = mpeg4Read(handle, at: offset + 8, count: 8), wide.count == 8 else { return nil }
                size = u64(wide, 0)
                headerLen = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerLen, offset + size <= end else { return nil }
            let payload = offset + headerLen
            let next = offset + size
            if type == "mvhd" {
                return mpeg4ParseMvhd(handle, at: payload, end: next)
            }
            if type == "moov" {
                if let found = mpeg4FindMvhd(handle, start: payload, end: next) {
                    return found
                }
            }
            offset = next
        }
        return nil
    }

    private static func mpeg4ParseMvhd(_ handle: FileHandle, at payload: UInt64, end: UInt64) -> Date? {
        guard end > payload, let head = mpeg4Read(handle, at: payload, count: 20), head.count >= 20 else { return nil }
        let version = head[0]
        let seconds: UInt64
        if version == 1 {
            guard head.count >= 20 else { return nil }
            seconds = u64(head, 4)
        } else {
            seconds = UInt64(u32(head, 4))
        }
        guard seconds > 0 else { return nil }
        return mpeg4Epoch.addingTimeInterval(TimeInterval(seconds))
    }

    private static func mpeg4Read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    private static func u32(_ data: Data, _ index: Int) -> UInt64 {
        UInt64(data[index]) << 24 | UInt64(data[index + 1]) << 16 | UInt64(data[index + 2]) << 8 | UInt64(data[index + 3])
    }

    private static func u64(_ data: Data, _ index: Int) -> UInt64 {
        u32(data, index) << 32 | u32(data, index + 4)
    }
}

/// CAF/M4A sitting in the recordings folder but not yet in SQLite (crash or force-quit).
public enum LectureOrphans: Sendable {
    public static func candidateURLs(in directory: URL, knownPaths: [String]) -> [URL] {
        let known = Set(knownPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "caf" || ext == "m4a" || ext == "wav" else { return false }
            return !known.contains(url.standardizedFileURL.path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
