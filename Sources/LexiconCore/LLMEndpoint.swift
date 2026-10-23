import Foundation

public enum LLMEndpointError: Error, Equatable, Sendable {
    case malformed
    case embeddedCredentials
    case insecureTransport
}

/// Client-side check for an OpenAI-compatible base URL.
/// http is allowed only for localhost, 127.0.0.1, and ::1. Credentials in the URL are never allowed.
public enum LLMEndpoint {
    public static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    public static func rootURL(from raw: String) -> Result<URL, LLMEndpointError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return .failure(.malformed)
        }
        if authorityContainsUserInfo(trimmed) {
            return .failure(.embeddedCredentials)
        }
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: base) else { return .failure(.malformed) }
        return validate(url)
    }

    public static func validate(_ url: URL) -> Result<URL, LLMEndpointError> {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.malformed)
        }
        guard var host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return .failure(.malformed)
        }
        host = host.lowercased()
        if host == "[::1]" { host = "::1" }
        guard url.query == nil, url.fragment == nil,
              !host.contains("%"), !host.contains(" "),
              url.port.map({ (1...65535).contains($0) }) ?? true else {
            return .failure(.malformed)
        }
        if url.user != nil || url.password != nil || host.contains("@") {
            return .failure(.embeddedCredentials)
        }
        if scheme != "https", !loopbackHosts.contains(host) {
            return .failure(.insecureTransport)
        }
        return .success(url)
    }

    public static func chatURL(from raw: String) -> Result<URL, LLMEndpointError> {
        switch rootURL(from: raw) {
        case .success(let root):
            return validate(root.appendingPathComponent("chat/completions"))
        case .failure(let error):
            return .failure(error)
        }
    }

    public static func modelsURL(from raw: String) -> Result<URL, LLMEndpointError> {
        switch rootURL(from: raw) {
        case .success(let root):
            return validate(root.appendingPathComponent("models"))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func authorityContainsUserInfo(_ raw: String) -> Bool {
        guard let scheme = raw.range(of: "://") else { return false }
        let rest = raw[scheme.upperBound...]
        let authority = rest.prefix { ch in
            ch != "/" && ch != "?" && ch != "#"
        }
        return authority.contains("@")
    }
}
