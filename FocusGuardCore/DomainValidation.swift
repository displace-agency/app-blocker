import Foundation
import FocusGuardShared

public enum DomainValidationError: Error, Equatable {
    case empty
    case nonASCII            // IDN not supported by hosts-file blocking
    case noDot
    case leadingTrailingDot
    case invalidCharacter
    case labelTooLong
    case tooLong
    case reserved

    /// Map to a stable command error code for the UI.
    public var commandError: CommandError {
        self == .reserved ? .reservedDomain : .invalidDomain
    }
}

public enum DomainValidation {
    /// Exact reserved names that must never be blocked (would break the machine).
    public static let reservedExact: Set<String> = [
        "localhost",
        "broadcasthost",
        "localhost.localdomain",
        "apple.com",
        "icloud.com",
    ]
    /// Reserved suffixes (protect OS update / push / loopback infrastructure).
    public static let reservedSuffixes: [String] = [
        ".local",
        ".apple.com",
        ".icloud.com",
    ]

    /// Normalize user input into a bare host: lowercase, strip scheme, www., path, port.
    public static func normalize(_ input: String) -> String {
        var domain = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] {
            if domain.hasPrefix(prefix) { domain = String(domain.dropFirst(prefix.count)) }
        }
        if domain.hasPrefix("www.") { domain = String(domain.dropFirst(4)) }
        if let slash = domain.firstIndex(of: "/") { domain = String(domain[domain.startIndex..<slash]) }
        if let colon = domain.firstIndex(of: ":") { domain = String(domain[domain.startIndex..<colon]) }
        return domain
    }

    /// Validate an already-normalized host string.
    public static func validate(_ domain: String) -> Result<String, DomainValidationError> {
        if domain.isEmpty { return .failure(.empty) }
        // ASCII only: reject IDN explicitly (unicode hosts won't match in /etc/hosts).
        guard domain.allSatisfy({ $0.isASCII }) else { return .failure(.nonASCII) }
        // Reserved check first so single-label infra names (localhost, broadcasthost)
        // are reported as reserved rather than "no dot".
        if isReserved(domain) { return .failure(.reserved) }
        if domain.hasPrefix(".") || domain.hasSuffix(".") { return .failure(.leadingTrailingDot) }
        guard domain.contains(".") else { return .failure(.noDot) }
        if domain.count > 253 { return .failure(.tooLong) }

        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard domain.allSatisfy({ allowed.contains($0) }) else { return .failure(.invalidCharacter) }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            if label.isEmpty { return .failure(.leadingTrailingDot) } // empty label = double dot
            if label.count > 63 { return .failure(.labelTooLong) }
            if label.hasPrefix("-") || label.hasSuffix("-") { return .failure(.invalidCharacter) }
        }

        return .success(domain)
    }

    public static func isReserved(_ domain: String) -> Bool {
        if reservedExact.contains(domain) { return true }
        for suffix in reservedSuffixes where domain.hasSuffix(suffix) { return true }
        return false
    }

    /// Convenience: normalize then validate.
    public static func clean(_ input: String) -> Result<String, DomainValidationError> {
        validate(normalize(input))
    }
}
