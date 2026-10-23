import Foundation
import LexiconCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Short on-device tags only. Does not replace the lecture summary request.
public enum OnDeviceLectureTags: Sendable {
    /// Far smaller than a 93-minute transcript.
    public static let maxPrefixChars = 1_800

    /// False when Apple Intelligence content tagging is off. Summaries still work.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel(useCase: .contentTagging).isAvailable
        }
        #endif
        return false
    }

    public static func prefix(_ transcript: String) -> String {
        String(transcript.prefix(maxPrefixChars))
    }

    public static func parseTags(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: "、", with: ",")
        return LectureTags.joined(LectureTags.list(collapsed))
    }

    public static func suggest(from transcript: String) async -> String? {
        let snippet = prefix(transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await suggestOnDevice(snippet: snippet)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func suggestOnDevice(snippet: String) async -> String? {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard model.isAvailable else { return nil }
        let session = LanguageModelSession(
            model: model,
            instructions: "Output 3 to 8 short topic tags for a lecture, comma-separated. No sentences."
        )
        do {
            let response = try await session.respond(to: snippet)
            let tags = parseTags(response.content)
            return tags.isEmpty ? nil : tags
        } catch {
            return nil
        }
    }
    #endif
}
