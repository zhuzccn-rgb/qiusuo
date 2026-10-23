import Foundation

public enum HomeworkStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case reviewed
    case archived
}

public struct Homework: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subject: String
    public var filePath: String
    public var notes: String
    public var status: HomeworkStatus
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        subject: String = "未分类",
        filePath: String = "",
        notes: String = "",
        status: HomeworkStatus = .inbox,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.filePath = filePath
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
    }

    public var fileURL: URL? {
        filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
    }

    public func matchesSearch(_ query: String) -> Bool {
        ArchiveSearch.matches(query, [
            title,
            subject,
            notes,
            URL(fileURLWithPath: filePath).lastPathComponent
        ])
    }
}

public struct Mistake: Identifiable, Hashable, Sendable {
    public var id: String
    public var homeworkId: String
    public var subject: String
    public var question: String
    public var wrongAnswer: String
    public var correctAnswer: String
    public var analysis: String
    public var tags: String
    public var imagePath: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        homeworkId: String = "",
        subject: String = "未分类",
        question: String,
        wrongAnswer: String = "",
        correctAnswer: String = "",
        analysis: String = "",
        tags: String = "",
        imagePath: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.homeworkId = homeworkId
        self.subject = subject
        self.question = question
        self.wrongAnswer = wrongAnswer
        self.correctAnswer = correctAnswer
        self.analysis = analysis
        self.tags = tags
        self.imagePath = imagePath
        self.createdAt = createdAt
    }

    public var imageURL: URL? {
        imagePath.isEmpty ? nil : URL(fileURLWithPath: imagePath)
    }

    public var hasAnalysis: Bool { !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var tagList: [String] { LectureTags.list(tags) }

    public func matchesSearch(_ query: String) -> Bool {
        ArchiveSearch.matches(query, [
            question,
            subject,
            tags,
            wrongAnswer,
            correctAnswer,
            analysis,
            URL(fileURLWithPath: imagePath).lastPathComponent
        ])
    }
}

public struct Lecture: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subject: String
    public var filePath: String
    public var transcript: String
    public var summary: String
    public var duration: TimeInterval
    public var createdAt: Date
    public var tags: String
    public var calendarEventId: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        subject: String = "未分类",
        filePath: String = "",
        transcript: String = "",
        summary: String = "",
        duration: TimeInterval = 0,
        createdAt: Date = Date(),
        tags: String = "",
        calendarEventId: String = ""
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.filePath = filePath
        self.transcript = transcript
        self.summary = summary
        self.duration = duration
        self.createdAt = createdAt
        self.tags = tags
        self.calendarEventId = calendarEventId
    }

    public var fileURL: URL? {
        filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
    }

    public var hasTranscript: Bool { !transcript.isEmpty }
    public var hasSummary: Bool { !summary.isEmpty }
    public var tagList: [String] { LectureTags.list(tags) }

    public func matchesSearch(_ query: String) -> Bool {
        ArchiveSearch.matches(query, [
            title,
            subject,
            tags,
            summary,
            transcript,
            URL(fileURLWithPath: filePath).lastPathComponent
        ])
    }
}

public enum SubjectPreset: String, CaseIterable, Identifiable, Sendable {
    case math = "数学"
    case physics = "物理"
    case chemistry = "化学"
    case english = "英语"
    case chinese = "语文"
    case coding = "编程"
    case other = "未分类"

    public var id: String { rawValue }
}

public enum LLMPreset: String, CaseIterable, Identifiable, Sendable {
    case llamaCpp = "llama.cpp"
    case lmStudio = "LM Studio"
    case hermes = "Hermes Agent"
    case openClaw = "OpenClaw"
    case ollama = "Ollama"
    case custom = "自定义"

    public var id: String { rawValue }

    public var defaultPort: Int {
        switch self {
        case .llamaCpp: return 8080
        case .lmStudio: return 1234
        case .hermes: return 8642
        case .openClaw: return 18789
        case .ollama: return 11434
        case .custom: return 8080
        }
    }

    /// Preset addresses stay on the loopback interface. Remote endpoints are typed in by hand.
    public var defaultBaseURL: String {
        "http://127.0.0.1:\(defaultPort)/v1"
    }

    public var defaultModel: String? {
        switch self {
        case .hermes: return "hermes-agent"
        case .openClaw: return "openclaw/default"
        default: return nil
        }
    }
}

/// Keep the configured model identifier visible without silently choosing another model.
public enum LLMModelChoice {
    public static func toolbarLabel(_ id: String) -> String { id }
}

public struct AppSettings: Equatable, Sendable {
    public var inboxPath: String
    public var llmPreset: LLMPreset
    public var llmBaseURL: String
    public var llmAPIKey: String
    public var llmModel: String
    public var speechLocale: String
    public var calendarExcludedIds: String
    /// System Voice Processing (AGC / noise reduction). Off by default: on macOS it can mute the tap.
    public var voiceProcessing: Bool

    public init(
        inboxPath: String = "",
        llmPreset: LLMPreset = .llamaCpp,
        llmBaseURL: String = "http://127.0.0.1:8080/v1",
        llmAPIKey: String = "",
        llmModel: String = "local",
        speechLocale: String = "en-US",
        calendarExcludedIds: String = "",
        voiceProcessing: Bool = false
    ) {
        self.inboxPath = inboxPath
        self.llmPreset = llmPreset
        self.llmBaseURL = llmBaseURL
        self.llmAPIKey = llmAPIKey
        self.llmModel = llmModel
        self.speechLocale = speechLocale
        self.calendarExcludedIds = calendarExcludedIds
        self.voiceProcessing = voiceProcessing
    }

    public var llmRootURL: URL? {
        if case .success(let url) = LLMEndpoint.rootURL(from: llmBaseURL) {
            return url
        }
        return nil
    }

    public var llmChatURL: URL? {
        llmRootURL?.appendingPathComponent("chat/completions")
    }

    public var llmModelsURL: URL? {
        llmRootURL?.appendingPathComponent("models")
    }

    /// Model id placed in the chat request. This is the name configured in settings.
    public var requestModel: String {
        llmModel
    }
}
