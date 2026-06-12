import Foundation

/// Rules for matching running processes against the app blocklist. Kept pure so
/// the kill decision can be unit-tested without enumerating real processes.
public enum AppMatchRules {
    public static let selfAppName = "FocusGuard"

    /// Validate a user-entered app name (not a path).
    public static func isValidAppName(_ name: String) -> Bool {
        let trimmed = normalize(name)
        guard (1...64).contains(trimmed.count) else { return false }
        if trimmed.contains("/") { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-")
        guard trimmed.allSatisfy({ allowed.contains($0) }) else { return false }
        if trimmed.caseInsensitiveCompare(selfAppName) == .orderedSame { return false }
        return true
    }

    /// Strip a trailing ".app" and surrounding whitespace.
    public static func normalize(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if n.lowercased().hasSuffix(".app") { n = String(n.dropLast(4)) }
        return n
    }

    /// Is this executable path inside a user-installed app bundle? Only such
    /// paths are eligible to be killed — this automatically protects everything
    /// under /System, /usr, /Library, etc. (Finder, Dock, WindowServer, daemons).
    public static func isUserApp(path: String) -> Bool {
        if path.hasPrefix("/Applications/") { return true }
        // /Users/<name>/Applications/...
        let comps = path.split(separator: "/", omittingEmptySubsequences: false)
        if comps.count >= 4, comps[1] == "Users", comps[3] == "Applications" { return true }
        return false
    }

    /// Should a process at `path` be killed given the blocklist? Kill iff the
    /// path is a user app AND contains a "<entry>.app" bundle component. The
    /// containment rule also catches helper processes nested inside the bundle.
    public static func shouldKill(path: String, blocklist: [String]) -> Bool {
        guard isUserApp(path: path) else { return false }
        let lower = path.lowercased()
        for entry in blocklist {
            let leaf = normalize(entry).lowercased()
            guard !leaf.isEmpty else { continue }
            if lower.contains("/\(leaf).app/") { return true }
            if lower.hasSuffix("/\(leaf).app") { return true }
        }
        return false
    }
}
