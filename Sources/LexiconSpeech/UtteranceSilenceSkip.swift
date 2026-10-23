import Foundation

/// Leading-silence skip for the old `SFSpeechRecognizer` utterance path only.
/// `SpeechDetector` cannot run without a transcriber, so this keeps the energy
/// check. It never rewrites the lecture file. The macOS 26 Analyzer path
/// does not call this.
public enum UtteranceSilenceSkip: Sendable {
    public static func skipLeading(reader: PCMReader, from seconds: TimeInterval) throws -> TimeInterval {
        try reader.skipSilence(from: seconds)
    }
}
