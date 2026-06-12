import Foundation

/// Daemon log with size-based rotation. The daemon owns its own log file (the
/// launchd plist routes only crash/startup output to a separate launchd log),
/// so it can rotate without launchd holding the descriptor open.
final class DaemonLogger {
    private let path: String
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "com.focusguard.log")
    private var handle: FileHandle?
    private let iso = ISO8601DateFormatter()

    init(path: String, maxBytes: Int = 2 * 1024 * 1024) {
        self.path = path
        self.maxBytes = maxBytes
        openHandle()
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: path)
        _ = try? handle?.seekToEnd()
    }

    func log(_ message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.rotateIfNeeded()
            let line = "[\(self.iso.string(from: Date()))] \(message)\n"
            if let data = line.data(using: .utf8) {
                self.handle?.write(data)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        try? handle?.close()
        let rotated = path + ".1"
        try? FileManager.default.removeItem(atPath: rotated)
        try? FileManager.default.moveItem(atPath: path, toPath: rotated)
        openHandle()
    }
}
