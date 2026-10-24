import Foundation
import EventKit
import LexiconCore

public struct CalendarClassMatch: Sendable, Equatable {
    public var eventId: String
    public var title: String
    public var subject: String?
    public var calendarTitle: String
    public var calendarId: String
    public var alignedStart: Date
}

public struct CalendarSource: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
}

public struct CalendarEventSnapshot: Sendable, Equatable {
    public var id: String
    public var title: String
    public var location: String
    public var start: Date
    public var end: Date
    public var calendarTitle: String
    public var calendarId: String

    public init(
        id: String,
        title: String,
        location: String,
        start: Date,
        end: Date,
        calendarTitle: String = "",
        calendarId: String = ""
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.calendarTitle = calendarTitle
        self.calendarId = calendarId
    }
}

@MainActor
public final class CalendarMatcher: ObservableObject {
    @Published public var status: EKAuthorizationStatus = .notDetermined
    @Published public var calendars: [CalendarSource] = []
    @Published private var lastRequestError: String?

    private var store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    public init() {
        refreshStatus()
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    public var isAuthorized: Bool {
        switch status {
        case .fullAccess: return true
        default: return false
        }
    }

    /// 按真实状态给话，不要一律叫用户去系统设置。
    /// `dist/求索.app` 是 adhoc 签名，重新打包 cdhash 会变，TCC 会把它当成另一个应用，
    /// 之前授过的权限就此失效——这时状态会退回「未决定」，需要重新同意一次。
    public var accessHint: String {
        switch status {
        case .notDetermined:
            if let lastRequestError, !lastRequestError.isEmpty {
                return L10n.text("系统没有弹出日历询问（\(lastRequestError)）。重新打包后签名会变，终端跑 tccutil reset Calendar app.lexicon.archive 再点这里。")
            }
            return L10n.text("点「允许读取日历」后系统会弹出询问。重新打包过的求索要再同意一次。")
        case .denied:
            return L10n.text("日历权限被拒绝了。系统设置 → 隐私与安全性 → 日历，把求索打开。")
        case .restricted:
            return L10n.text("这台 Mac 的描述文件禁止访问日历。")
        case .writeOnly:
            return L10n.text("现在只给了「仅添加日程」，读不到课表。系统设置 → 隐私与安全性 → 日历，把求索改成完全访问。")
        case .fullAccess:
            return L10n.text("日历权限正常。")
        @unknown default:
            return L10n.text("拿不到日历权限（状态 \(status.rawValue)）。")
        }
    }

    private var isIsolatedDemo: Bool {
        ProcessInfo.processInfo.environment["QIUSUO_DATA_DIRECTORY"]?.hasPrefix("/") == true
    }

    public func refreshStatus() {
        guard !isIsolatedDemo else {
            status = .notDetermined
            calendars = []
            return
        }
        status = EKEventStore.authorizationStatus(for: .event)
        if isAuthorized {
            loadCalendars()
        }
    }

    public func requestAccess() async -> Bool {
        guard !isIsolatedDemo else { return false }
        lastRequestError = nil
        // 完成回调在后台队列；挂起 MainActor，让 NSApp 跑起来才能弹出 TCC 窗。
        let result: (Bool, Error?) = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                continuation.resume(returning: (granted, error))
            }
        }
        if result.0 {
            // 授权前建的 store 里没有日历。换一份才能读课表。
            store = EKEventStore()
        }
        if let error = result.1 {
            lastRequestError = error.localizedDescription
        }
        refreshStatus()
        return isAuthorized
    }

    public func loadCalendars() {
        guard !isIsolatedDemo else { return }
        calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { CalendarSource(id: $0.calendarIdentifier, title: $0.title) }
    }

    nonisolated public static let matchSlack: TimeInterval = 10 * 60

    public func match(
        start: Date,
        duration: TimeInterval,
        excludedCalendarIds: Set<String>,
        placeHint: String = ""
    ) -> CalendarClassMatch? {
        let span = Self.recordingSpan(start: start, duration: duration)
        return match(
            intervals: [RecordingSpan(start: span.start, end: span.end, anchor: .filenameStart)],
            excludedCalendarIds: excludedCalendarIds,
            placeHint: placeHint
        )
    }

    public func match(
        intervals: [RecordingSpan],
        excludedCalendarIds: Set<String>,
        placeHint: String = ""
    ) -> CalendarClassMatch? {
        guard isAuthorized, let first = intervals.first else { return nil }
        let windowStart = (intervals.map(\.start).min() ?? first.start).addingTimeInterval(-Self.matchSlack)
        let windowEnd = (intervals.map(\.end).max() ?? first.end).addingTimeInterval(Self.matchSlack)

        let included = store.calendars(for: .event).filter { !excludedCalendarIds.contains($0.calendarIdentifier) }
        guard !included.isEmpty else { return nil }

        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: included)
        let snapshots: [CalendarEventSnapshot] = store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, let eventStart = event.startDate, let eventEnd = event.endDate else { return nil }
            return CalendarEventSnapshot(
                id: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title ?? "",
                location: event.location ?? "",
                start: eventStart,
                end: eventEnd,
                calendarTitle: event.calendar.title,
                calendarId: event.calendar.calendarIdentifier
            )
        }
        guard let picked = Self.pickBest(intervals: intervals, events: snapshots, placeHint: placeHint) else {
            return nil
        }
        return CalendarClassMatch(
            eventId: picked.event.id,
            title: picked.event.title,
            subject: Self.inferredSubject(from: picked.event.title),
            calendarTitle: picked.event.calendarTitle,
            calendarId: picked.event.calendarId,
            alignedStart: picked.alignedStart
        )
    }

    public struct CalendarPick: Sendable, Equatable {
        public var event: CalendarEventSnapshot
        public var alignedStart: Date
    }

    /// Rank then score. Lower rank wins so a late-saved Voice Memo does not get
    /// assigned to the next class just because that wrong window overlaps more.
    nonisolated public static func pickBest(
        intervals: [RecordingSpan],
        events: [CalendarEventSnapshot],
        placeHint: String = ""
    ) -> CalendarPick? {
        var best: (pick: CalendarPick, rank: Int, score: TimeInterval)?
        for event in events {
            for span in intervals {
                guard let rank = matchRank(
                    recStart: span.start,
                    recEnd: span.end,
                    eventStart: event.start,
                    eventEnd: event.end,
                    anchor: span.anchor
                ) else { continue }
                var score = matchScore(
                    recStart: span.start,
                    recEnd: span.end,
                    eventStart: event.start,
                    eventEnd: event.end
                )
                score += placeBoost(placeHint: placeHint, title: event.title, location: event.location)
                if let current = best {
                    if rank > current.rank { continue }
                    if rank == current.rank, score <= current.score { continue }
                }
                best = (CalendarPick(event: event, alignedStart: span.start), rank, score)
            }
        }
        return best?.pick
    }

    /// 0 = started with the class, 1 = ended with the class, 2 = filename overlap,
    /// 3 = saved-at-end overlap. `creationAsStart` overlap-only is rejected so a
    /// file saved after class cannot steal the following lecture.
    nonisolated public static func matchRank(
        recStart: Date,
        recEnd: Date,
        eventStart: Date,
        eventEnd: Date,
        anchor: RecordingTimeAnchor,
        slack: TimeInterval = matchSlack
    ) -> Int? {
        guard matchesEvent(
            recStart: recStart,
            recEnd: recEnd,
            eventStart: eventStart,
            eventEnd: eventEnd,
            slack: slack
        ) else { return nil }
        let startAligned = abs(recStart.timeIntervalSince(eventStart)) <= slack
        let endAligned = abs(recEnd.timeIntervalSince(eventEnd)) <= slack
        switch anchor {
        case .filenameStart, .mediaStart:
            if startAligned { return 0 }
            if endAligned { return 1 }
            return 2
        case .creationAsEnd:
            if startAligned { return 0 }
            if endAligned { return 1 }
            return 3
        case .creationAsStart:
            guard startAligned else { return nil }
            return 0
        }
    }

    nonisolated public static func inferredSubject(from title: String) -> String? {
        let t = title.lowercased()
        if title.contains("数学") || t.contains("math") { return SubjectPreset.math.rawValue }
        if title.contains("物理") || t.contains("physics") { return SubjectPreset.physics.rawValue }
        if title.contains("化学") || t.contains("chem") { return SubjectPreset.chemistry.rawValue }
        if title.contains("英语") || t.contains("english") { return SubjectPreset.english.rawValue }
        if title.contains("语文") || t.contains("chinese") { return SubjectPreset.chinese.rawValue }
        if title.contains("编程") || title.contains("计算机") || t.contains("python") || t.contains(" cs") || t.hasPrefix("cs") || t.contains("coding") || t.contains("comp sci") {
            return SubjectPreset.coding.rawValue
        }
        return nil
    }

    nonisolated public static func recordingSpan(start: Date, duration: TimeInterval) -> (start: Date, end: Date) {
        let span = (duration.isFinite && duration > 30) ? duration : 90 * 60
        return (start, start.addingTimeInterval(span))
    }

    /// Start within 10 minutes of class start, end within 10 minutes of class end,
    /// or any overlap with the class itself.
    nonisolated public static func matchesEvent(
        recStart: Date,
        recEnd: Date,
        eventStart: Date,
        eventEnd: Date,
        slack: TimeInterval = matchSlack
    ) -> Bool {
        if overlapDuration(aStart: recStart, aEnd: recEnd, bStart: eventStart, bEnd: eventEnd) > 0 {
            return true
        }
        if abs(recStart.timeIntervalSince(eventStart)) <= slack { return true }
        if abs(recEnd.timeIntervalSince(eventEnd)) <= slack { return true }
        return false
    }

    nonisolated public static func matchScore(
        recStart: Date,
        recEnd: Date,
        eventStart: Date,
        eventEnd: Date
    ) -> TimeInterval {
        let overlap = max(0, overlapDuration(aStart: recStart, aEnd: recEnd, bStart: eventStart, bEnd: eventEnd))
        let nearest = min(
            abs(recStart.timeIntervalSince(eventStart)),
            abs(recEnd.timeIntervalSince(eventEnd))
        )
        return overlap * 2 - nearest
    }

    nonisolated public static func placeBoost(placeHint: String, title: String, location: String) -> TimeInterval {
        let hint = placeHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hint.count >= 3 else { return 0 }
        if location.localizedStandardContains(hint) || title.localizedStandardContains(hint) {
            return 15 * 60
        }
        let head = hint.split(separator: " ").first.map(String.init) ?? hint
        if head.count >= 3, location.localizedStandardContains(head) || title.localizedStandardContains(head) {
            return 10 * 60
        }
        return 0
    }

    nonisolated public static func overlapDuration(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> TimeInterval {
        let start = max(aStart, bStart)
        let end = min(aEnd, bEnd)
        return end.timeIntervalSince(start)
    }
}
