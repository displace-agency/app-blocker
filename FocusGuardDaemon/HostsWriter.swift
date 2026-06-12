import Foundation
import FocusGuardShared
import FocusGuardCore

/// Builds and writes the FocusGuard-managed block in /etc/hosts. Writes are
/// atomic (temp-in-/etc + rename) with explicit root:wheel 0644 ownership so a
/// mid-write crash can never leave /etc/hosts truncated or unreadable.
enum HostsWriter {
    static let markerStart = FocusGuardConfig.lockMarkerStart
    static let markerEnd = FocusGuardConfig.lockMarkerEnd
    static let hostsFile = FocusGuardConfig.hostsFile

    static func buildBlockEntries(for domains: [String]) -> String {
        var lines: [String] = [markerStart]
        for domain in domains {
            // Defense-in-depth: never emit a domain with whitespace/control chars
            // (validation should already have caught these).
            if domain.contains(where: { $0.isWhitespace || $0 == "\n" || $0 == "\t" }) { continue }
            lines.append("127.0.0.1 \(domain)")
            lines.append("127.0.0.1 www.\(domain)")
            lines.append("::1 \(domain)")
            lines.append("::1 www.\(domain)")
        }
        lines.append(markerEnd)
        return lines.joined(separator: "\n")
    }

    static func readHostsWithoutBlock() -> String {
        guard let contents = try? String(contentsOfFile: hostsFile, encoding: .utf8) else {
            return "127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n::1\tlocalhost\n"
        }
        var result: [String] = []
        var inBlock = false
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == markerStart { inBlock = true; continue }
            if trimmed == markerEnd { inBlock = false; continue }
            if !inBlock { result.append(line) }
        }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    static func expectedHosts(domains: [String]) -> String {
        readHostsWithoutBlock() + "\n\n" + buildBlockEntries(for: domains) + "\n"
    }

    static func cleanHosts() -> String {
        readHostsWithoutBlock() + "\n"
    }

    static func currentHosts() -> String {
        (try? String(contentsOfFile: hostsFile, encoding: .utf8)) ?? ""
    }

    static func write(_ content: String, log: (String) -> Void) {
        if !AtomicFile.writeString(content, to: hostsFile, mode: 0o644, owner: 0, group: 0) {
            log("Failed to write /etc/hosts atomically")
        }
    }
}
