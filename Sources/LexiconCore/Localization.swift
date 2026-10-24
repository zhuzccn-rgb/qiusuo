import Foundation

/// Shared by SwiftUI, AppKit dialogs and library errors. Archive values stay stable.
public enum L10n {
    public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let key: String
        let arguments: [String]

        public init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            public mutating func appendLiteral(_ literal: String) { key += literal }
            public mutating func appendInterpolation<T>(_ value: T) {
                key += "%@"
                arguments.append(String(describing: value))
            }
        }
    }

    public static func language(for preferredLanguages: [String]) -> String {
        for language in preferredLanguages {
            let code = language.lowercased().split(separator: "-").first.map(String.init)
            if code == "zh" { return "zh-Hans" }
            if code == "en" { return "en" }
        }
        return "en"
    }

    private static let systemLanguage = language(for: Locale.preferredLanguages)
    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for language in ["en", "zh-Hans"] {
            if let path = Bundle.module.path(forResource: language, ofType: "lproj"),
               let bundle = Bundle(path: path) { result[language] = bundle }
        }
        return result
    }()

    public static func lookup(_ key: String, language: String? = nil) -> String {
        let selected = language.map { self.language(for: [$0]) } ?? systemLanguage
        return bundles[selected]?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    public static func text(_ message: Message, language: String? = nil) -> String {
        let format = lookup(message.key, language: language)
        guard !message.arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: message.arguments)
    }

    public static func subject(_ value: String) -> String {
        SubjectPreset(rawValue: value) == nil ? value : lookup(value)
    }
}
