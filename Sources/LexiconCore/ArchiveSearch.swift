import Foundation

/// Inclusive day range plus a course name. Empty course and nil dates leave the list alone.
public struct LectureBrowseFilter: Equatable, Sendable {
    public var start: Date?
    public var end: Date?
    public var course: String

    public init(start: Date? = nil, end: Date? = nil, course: String = "") {
        self.start = start
        self.end = end
        self.course = course
    }

    public var isActive: Bool {
        start != nil || end != nil || !Self.normalized(course).isEmpty
    }

    /// Calendar event title when the recording was matched; otherwise the subject.
    public static func courseName(of lecture: Lecture) -> String {
        let title = lecture.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let subject = lecture.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "未命名" : subject
    }

    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct LectureCourseGroup: Equatable, Sendable {
    public var course: String
    public var lectures: [Lecture]

    public init(course: String, lectures: [Lecture]) {
        self.course = course
        self.lectures = lectures
    }
}

/// Shared list search. Matching uses `localizedStandardContains` (system default: case, diacritic, locale).
public enum ArchiveSearch {
    public static func query(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func matches(_ rawQuery: String, _ fields: [String]) -> Bool {
        let q = query(rawQuery)
        if q.isEmpty { return true }
        return fields.contains { $0.localizedStandardContains(q) }
    }

    public static func apply<S: Sequence>(
        _ items: S,
        query raw: String,
        matches: (S.Element) -> Bool
    ) -> [S.Element] {
        if self.query(raw).isEmpty { return Array(items) }
        return items.filter(matches)
    }

    public static func suggestions(from values: [String], query raw: String, limit: Int = 8) -> [String] {
        let q = query(raw)
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            if q.isEmpty || trimmed.localizedStandardContains(q) {
                out.append(trimmed)
                if out.count >= limit { break }
            }
        }
        return out
    }

    public static func item<T: Identifiable>(_ items: [T], id: T.ID?) -> T? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// FTS5 MATCH string. Nil means "do not query FTS".
    public static func ftsMatchQuery(_ raw: String) -> String? {
        let q = query(raw)
        if q.isEmpty { return nil }
        let cleaned = q.replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        let tokens = cleaned.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        if tokens.count == 1 { return tokens[0] }
        return tokens.map { "\"\($0)\"" }.joined(separator: " AND ")
    }

    /// Date bounds are inclusive calendar days. Empty `course` keeps every course.
    /// A reversed range is treated as the span between the two days.
    public static func applyBrowseFilter(
        _ lectures: [Lecture],
        filter: LectureBrowseFilter,
        calendar: Calendar = .current
    ) -> [Lecture] {
        let course = LectureBrowseFilter.normalized(filter.course)
        var lower = filter.start.map { calendar.startOfDay(for: $0) }
        var upper = filter.end.map { calendar.startOfDay(for: $0) }
        if let low = lower, let high = upper, low > high {
            lower = high
            upper = low
        }
        if course.isEmpty, lower == nil, upper == nil { return lectures }
        return lectures.filter { lecture in
            if !course.isEmpty {
                let name = LectureBrowseFilter.courseName(of: lecture)
                if name.localizedCaseInsensitiveCompare(course) != .orderedSame { return false }
            }
            if lower != nil || upper != nil {
                let day = calendar.startOfDay(for: lecture.createdAt)
                if let lower, day < lower { return false }
                if let upper, day > upper { return false }
            }
            return true
        }
    }

    /// First-seen order. Lectures stay in the order they arrived (newest first when the store is).
    public static func groupByCourse(_ lectures: [Lecture]) -> [LectureCourseGroup] {
        var order: [String] = []
        var keys: [String] = []
        var buckets: [String: [Lecture]] = [:]
        for lecture in lectures {
            let name = LectureBrowseFilter.courseName(of: lecture)
            let key = name.lowercased()
            if buckets[key] == nil {
                order.append(name)
                keys.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(lecture)
        }
        return zip(order, keys).map { name, key in
            LectureCourseGroup(course: name, lectures: buckets[key] ?? [])
        }
    }

    public static func courseNames(in lectures: [Lecture]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for lecture in lectures {
            let name = LectureBrowseFilter.courseName(of: lecture)
            guard seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// `ftsIDs == nil` falls back to `localizedStandardContains`. Empty `ftsIDs` is a real miss.
    public static func applyLectures(_ lectures: [Lecture], query raw: String, ftsIDs: [String]?) -> [Lecture] {
        if query(raw).isEmpty { return lectures }
        if let ftsIDs {
            let set = Set(ftsIDs)
            return lectures.filter { set.contains($0.id) }
        }
        return lectures.filter { $0.matchesSearch(raw) }
    }
}
