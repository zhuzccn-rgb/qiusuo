import AppKit
import Foundation
import PDFKit
import Vision

/// Homework / mistake OCR. Never touches lecture audio. Writes only when notes are empty.
public enum DocumentTextRecognizer: Sendable {
    public static let maxPDFPages = 8

    public static func shouldFillEmptyNotes(_ notes: String) -> Bool {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func recognize(url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentTextRecognizerError.missingFile
        }
        let ext = url.pathExtension.lowercased()
        let text: String
        if ext == "pdf" {
            text = try await recognizePDF(url: url)
        } else if Self.imageExtensions.contains(ext) {
            text = try await recognizeImage(url: url)
        } else {
            throw DocumentTextRecognizerError.unsupportedType
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DocumentTextRecognizerError.emptyResult }
        return trimmed
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "webp", "gif", "bmp"
    ]

    private static func recognizePDF(url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentTextRecognizerError.unsupportedType
        }
        var pages: [String] = []
        let count = min(document.pageCount, maxPDFPages)
        for index in 0..<count {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = cgImage(from: image) else { continue }
            let pageText = try await recognizeCGImage(cgImage)
            if !pageText.isEmpty { pages.append(pageText) }
        }
        return pages.joined(separator: "\n\n")
    }

    private static func recognizeImage(url: URL) async throws -> String {
        if let image = NSImage(contentsOf: url), let cgImage = cgImage(from: image) {
            return try await recognizeCGImage(cgImage)
        }
        return try await recognizeURL(url)
    }

    private static func recognizeURL(_ url: URL) async throws -> String {
        if #available(macOS 26.0, *) {
            return try await documentsText { try await $0.perform(on: url) }
        }
        if #available(macOS 15.0, *) {
            return try await legacyText { try await $0.perform(on: url) }
        }
        return try recognizeWithVN(url: url)
    }

    private static func recognizeCGImage(_ image: CGImage) async throws -> String {
        if #available(macOS 26.0, *) {
            return try await documentsText { try await $0.perform(on: image) }
        }
        if #available(macOS 15.0, *) {
            return try await legacyText { try await $0.perform(on: image) }
        }
        return try recognizeWithVN(image: image)
    }

    @available(macOS 26.0, *)
    private static func documentsText(
        _ run: (RecognizeDocumentsRequest) async throws -> [DocumentObservation]
    ) async throws -> String {
        let request = RecognizeDocumentsRequest()
        let observations = try await run(request)
        return observations
            .map { observation in
                let title = observation.document.title?.transcript ?? ""
                let body = observation.document.text.transcript
                if title.isEmpty { return body }
                if body.hasPrefix(title) { return body }
                return title + "\n" + body
            }
            .joined(separator: "\n\n")
    }

    @available(macOS 15.0, *)
    private static func legacyText(
        _ run: (RecognizeTextRequest) async throws -> [RecognizedTextObservation]
    ) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let observations = try await run(request)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func recognizeWithVN(url: URL) throws -> String {
        try runVN { VNImageRequestHandler(url: url) }
    }

    private static func recognizeWithVN(image: CGImage) throws -> String {
        try runVN { VNImageRequestHandler(cgImage: image) }
    }

    private static func runVN(_ makeHandler: () -> VNImageRequestHandler) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try makeHandler().perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

public enum DocumentTextRecognizerError: LocalizedError {
    case missingFile
    case unsupportedType
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .missingFile:
            return "找不到这份文件。"
        case .unsupportedType:
            return "这类文件还不能识别文字。"
        case .emptyResult:
            return "没有识别到文字。"
        }
    }
}
