import Foundation
import Darwin
import FocusGuardCore

/// Kills processes belonging to blocked apps. Uses libproc to enumerate full
/// executable paths (avoids pgrep's 16-char truncation and per-tick spawns).
/// Only user-app paths are eligible — system processes are auto-protected by
/// AppMatchRules.isUserApp.
enum AppBlocker {
    static func enumerateProcesses() -> [(pid: pid_t, path: String)] {
        let cap = proc_listallpids(nil, 0)
        guard cap > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(cap) + 64)
        let returned = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard returned > 0 else { return [] }
        let count = Int(returned) / MemoryLayout<pid_t>.size

        var result: [(pid_t, String)] = []
        // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) is not exported to Swift.
        let pathMax = 4 * Int(MAXPATHLEN)
        var buf = [CChar](repeating: 0, count: pathMax)
        for i in 0..<min(count, pids.count) {
            let pid = pids[i]
            if pid <= 1 { continue }
            let len = proc_pidpath(pid, &buf, UInt32(buf.count))
            if len > 0 {
                result.append((pid, String(cString: buf)))
            }
        }
        return result
    }

    /// Kill all running processes matching the blocklist. Returns the kill count.
    @discardableResult
    static func killBlockedApps(_ blocklist: [String], log: (String) -> Void) -> Int {
        guard !blocklist.isEmpty else { return 0 }
        let myPid = getpid()
        var killed = 0
        for proc in enumerateProcesses() {
            if proc.pid == myPid { continue }
            if AppMatchRules.shouldKill(path: proc.path, blocklist: blocklist) {
                if kill(proc.pid, SIGKILL) == 0 {
                    killed += 1
                    log("Killed blocked app: \(proc.path) (pid \(proc.pid))")
                }
            }
        }
        return killed
    }
}
