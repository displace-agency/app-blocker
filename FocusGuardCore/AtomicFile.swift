import Foundation

/// Crash-safe file writes: write to a temp file in the SAME directory, fsync,
/// set ownership/mode, then rename(2) over the destination. rename is atomic
/// within a filesystem and preserves the temp's perms, so we chmod/chown the
/// temp BEFORE the rename — never leaving a half-written or wrong-perms file.
public enum AtomicFile {
    private static let keepGroup = gid_t(bitPattern: Int32(-1)) // sentinel: "don't change group"

    @discardableResult
    public static func write(
        _ data: Data,
        to path: String,
        mode: mode_t = 0o644,
        owner: uid_t? = nil,
        group: gid_t? = nil
    ) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let tmp = "\(dir)/.\(name).tmp.\(getpid())"

        let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, mode)
        guard fd >= 0 else { return false }

        var ok = true
        if !data.isEmpty {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { ok = false; return }
                var written = 0
                let total = raw.count
                while written < total {
                    let n = Darwin.write(fd, base + written, total - written)
                    if n <= 0 { ok = false; break }
                    written += n
                }
            }
        }

        if ok { ok = (fchmod(fd, mode) == 0) }
        if ok, let owner = owner { _ = fchown(fd, owner, group ?? keepGroup) }
        if ok { ok = (fsync(fd) == 0) }
        close(fd)

        if !ok { unlink(tmp); return false }
        if rename(tmp, path) != 0 { unlink(tmp); return false }
        return true
    }

    @discardableResult
    public static func writeString(
        _ string: String,
        to path: String,
        mode: mode_t = 0o644,
        owner: uid_t? = nil,
        group: gid_t? = nil
    ) -> Bool {
        write(Data(string.utf8), to: path, mode: mode, owner: owner, group: group)
    }
}
