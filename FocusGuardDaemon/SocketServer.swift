import Foundation
import Darwin
import FocusGuardShared

/// Unix-domain socket command server. Replaces the old world-writable
/// /tmp command file. Authenticates the peer by UID (root or the current
/// console user only) and replies with a CommandResponse acknowledgement.
final class SocketServer {
    private let path: String
    private let stateQueue: DispatchQueue
    private let handler: (CommandMessage) -> CommandResponse
    private let log: (String) -> Void
    private var listenFD: Int32 = -1

    init(
        path: String,
        stateQueue: DispatchQueue,
        log: @escaping (String) -> Void,
        handler: @escaping (CommandMessage) -> CommandResponse
    ) {
        self.path = path
        self.stateQueue = stateQueue
        self.handler = handler
        self.log = log
    }

    func start() {
        unlink(path) // clear any stale socket

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { log("socket() failed: \(errno)"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        _ = path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: maxLen + 1) { cdst in
                    strncpy(cdst, src, maxLen)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, size)
            }
        }
        guard bindResult == 0 else {
            log("bind() failed: \(errno)")
            close(listenFD)
            listenFD = -1
            return
        }

        chmod(path, 0o666) // auth is by peer UID, not file perms
        guard listen(listenFD, 8) == 0 else {
            log("listen() failed: \(errno)")
            close(listenFD)
            listenFD = -1
            return
        }

        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "com.focusguard.socket"
        thread.start()
        log("Socket server listening at \(path)")
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        // Peer authentication: allow root or the current console (logged-in) user.
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, isAuthorized(uid) else {
            writeResponse(fd, CommandResponse(ok: false, error: .unauthorized))
            return
        }

        guard let data = readRequest(fd), !data.isEmpty,
              let message = try? JSONDecoder().decode(CommandMessage.self, from: data) else {
            writeResponse(fd, CommandResponse(ok: false, error: .invalidArgument))
            return
        }

        // Serialize all state changes onto the daemon's state queue.
        let response = stateQueue.sync { handler(message) }
        writeResponse(fd, response)
    }

    private func isAuthorized(_ uid: uid_t) -> Bool {
        if uid == 0 { return true }
        var st = stat()
        if stat("/dev/console", &st) == 0, st.st_uid == uid { return true }
        return false
    }

    private func readRequest(_ fd: Int32, max: Int = 64 * 1024, timeoutSec: Int = 5) -> Data? {
        var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < max {
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if let nl = data.firstIndex(of: 0x0A) {
                return data[data.startIndex..<nl]
            }
        }
        return data
    }

    private func writeResponse(_ fd: Int32, _ response: CommandResponse) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let n = send(fd, base + written, raw.count - written, 0)
                if n <= 0 { break }
                written += n
            }
        }
    }
}
