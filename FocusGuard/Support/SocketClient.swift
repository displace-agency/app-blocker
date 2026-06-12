import Foundation
import Darwin
import FocusGuardShared

/// Low-level Unix-socket round-trip to the daemon. Sends one CommandMessage and
/// awaits one CommandResponse. Blocking work runs off the main thread.
enum SocketClient {
    static func send(_ message: CommandMessage, timeout: TimeInterval = 6) async -> CommandResponse? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: sendSync(message, timeout: timeout))
            }
        }
    }

    private static func sendSync(_ message: CommandMessage, timeout: TimeInterval) -> CommandResponse? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        _ = FocusGuardConfig.socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: maxLen + 1) { strncpy($0, src, maxLen) }
            }
        }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { return nil }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var payload = try? encoder.encode(message) else { return nil }
        payload.append(0x0A)

        let sent = payload.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var written = 0
            while written < raw.count {
                let n = Darwin.send(fd, base + written, raw.count - written, 0)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
        guard sent else { return nil }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 256 * 1024 {
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if let nl = data.firstIndex(of: 0x0A) {
                data = Data(data[data.startIndex..<nl])
                break
            }
        }
        guard !data.isEmpty else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CommandResponse.self, from: data)
    }
}
