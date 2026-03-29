import Foundation
import FocusGuardShared

// MARK: - Configuration

let configDir = FocusGuardConfig.configDir
let blockedFile = FocusGuardConfig.blockedFile
let hostsFile = FocusGuardConfig.hostsFile
let unlockFile = FocusGuardConfig.unlockFile
let statusFile = FocusGuardConfig.statusFile
let configFile = FocusGuardConfig.configFile
let commandFile = FocusGuardConfig.commandFile
let markerStart = FocusGuardConfig.lockMarkerStart
let markerEnd = FocusGuardConfig.lockMarkerEnd

// MARK: - Helpers

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

struct DaemonConfig {
    var unlockDelay: Int
    var maxUnlocksPerDay: Int
    var cooldownDuration: Int
}

func readConfig() -> DaemonConfig {
    guard let data = FileManager.default.contents(atPath: configFile),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return DaemonConfig(
            unlockDelay: FocusGuardConfig.defaultUnlockDelay,
            maxUnlocksPerDay: FocusGuardConfig.defaultMaxUnlocksPerDay,
            cooldownDuration: FocusGuardConfig.defaultCooldownDuration
        )
    }
    return DaemonConfig(
        unlockDelay: json["unlockDelay"] as? Int ?? FocusGuardConfig.defaultUnlockDelay,
        maxUnlocksPerDay: json["maxUnlocksPerDay"] as? Int ?? FocusGuardConfig.defaultMaxUnlocksPerDay,
        cooldownDuration: json["cooldownDuration"] as? Int ?? FocusGuardConfig.defaultCooldownDuration
    )
}

// MARK: - Unlock History (escalating delays + daily budget)

struct UnlockHistory: Codable {
    var entries: [UnlockEntry]

    struct UnlockEntry: Codable {
        var date: String // "YYYY-MM-DD"
        var timestamp: Double
    }
}

let historyFile = FocusGuardConfig.unlockHistoryFile
let cooldownFile = "\(configDir)/.cooldown_end"

func readUnlockHistory() -> UnlockHistory {
    guard let data = FileManager.default.contents(atPath: historyFile),
          let history = try? JSONDecoder().decode(UnlockHistory.self, from: data) else {
        return UnlockHistory(entries: [])
    }
    return history
}

func writeUnlockHistory(_ history: UnlockHistory) {
    if let data = try? JSONEncoder().encode(history) {
        FileManager.default.createFile(atPath: historyFile, contents: data)
    }
}

func todayString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

func unlocksToday() -> Int {
    let history = readUnlockHistory()
    let today = todayString()
    return history.entries.filter { $0.date == today }.count
}

func recordUnlock() {
    var history = readUnlockHistory()
    let entry = UnlockHistory.UnlockEntry(date: todayString(), timestamp: Date().timeIntervalSince1970)
    history.entries.append(entry)
    // Prune entries older than 7 days to keep file small
    let sevenDaysAgo = Date().timeIntervalSince1970 - 7 * 86400
    history.entries = history.entries.filter { $0.timestamp > sevenDaysAgo }
    writeUnlockHistory(history)
    log("Recorded unlock #\(unlocksToday()) for today")
}

/// Escalating delay: base delay * 2^(unlocks_today)
func currentUnlockDelay(baseDelay: Int) -> Int {
    let count = unlocksToday()
    let multiplier = 1 << count // 2^count: 1x, 2x, 4x, 8x...
    return baseDelay * multiplier
}

// MARK: - Cooldown (auto-relock timer)

func readCooldownEnd() -> Date? {
    guard let data = FileManager.default.contents(atPath: cooldownFile),
          let timestamp = try? JSONDecoder().decode(Double.self, from: data) else {
        return nil
    }
    return Date(timeIntervalSince1970: timestamp)
}

func writeCooldownEnd(_ date: Date) {
    if let data = try? JSONEncoder().encode(date.timeIntervalSince1970) {
        FileManager.default.createFile(atPath: cooldownFile, contents: data)
        log("Cooldown set: auto-relock at \(date)")
    }
}

func deleteCooldownFile() {
    try? FileManager.default.removeItem(atPath: cooldownFile)
}

func readBlockedDomains() -> [String] {
    guard let contents = try? String(contentsOfFile: blockedFile, encoding: .utf8) else {
        return []
    }
    return contents
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

func runShell(_ command: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        log("Failed to run: \(command) - \(error)")
    }
}

func flushDNS() {
    runShell("dscacheutil -flushcache")
    runShell("killall -HUP mDNSResponder")
}

// MARK: - Hosts File Management

func buildBlockEntries(for domains: [String]) -> String {
    var lines: [String] = []
    lines.append(markerStart)
    for domain in domains {
        lines.append("127.0.0.1 \(domain)")
        lines.append("127.0.0.1 www.\(domain)")
        lines.append("::1 \(domain)")
        lines.append("::1 www.\(domain)")
    }
    lines.append(markerEnd)
    return lines.joined(separator: "\n")
}

func readHostsWithoutBlock() -> String {
    guard let contents = try? String(contentsOfFile: hostsFile, encoding: .utf8) else {
        return "127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n::1\tlocalhost\n"
    }

    var result: [String] = []
    var inBlock = false

    for line in contents.components(separatedBy: .newlines) {
        if line.trimmingCharacters(in: .whitespaces) == markerStart {
            inBlock = true
            continue
        }
        if line.trimmingCharacters(in: .whitespaces) == markerEnd {
            inBlock = false
            continue
        }
        if !inBlock {
            result.append(line)
        }
    }

    while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
        result.removeLast()
    }

    return result.joined(separator: "\n")
}

func writeBlocks(domains: [String]) {
    let clean = readHostsWithoutBlock()
    let block = buildBlockEntries(for: domains)
    let content = clean + "\n\n" + block + "\n"

    // Write directly (not atomically) to avoid temp file issues with protected dirs
    do {
        try content.write(toFile: hostsFile, atomically: false, encoding: .utf8)
    } catch {
        log("Failed to write \(hostsFile): \(error)")
    }
}

func removeBlocks() {
    let clean = readHostsWithoutBlock()
    let content = clean + "\n"

    do {
        try content.write(toFile: hostsFile, atomically: false, encoding: .utf8)
    } catch {
        log("Failed to write \(hostsFile): \(error)")
    }
}

// MARK: - Unlock File

func readUnlockRequestTime() -> Date? {
    guard let data = FileManager.default.contents(atPath: unlockFile),
          let timestamp = try? JSONDecoder().decode(Double.self, from: data) else {
        return nil
    }
    return Date(timeIntervalSince1970: timestamp)
}

func writeUnlockFile() {
    let timestamp = Date().timeIntervalSince1970
    if let data = try? JSONEncoder().encode(timestamp) {
        FileManager.default.createFile(atPath: unlockFile, contents: data)
    }
}

func deleteUnlockFile() {
    try? FileManager.default.removeItem(atPath: unlockFile)
}

// MARK: - Status Reporting

func writeStatus(_ status: StatusInfo) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted

    do {
        let data = try encoder.encode(status)
        // Write directly, not atomically
        try data.write(to: URL(fileURLWithPath: statusFile))
    } catch {
        log("Failed to write status: \(error)")
    }
}

// MARK: - File Protection (immutable flags)
//
// IMPORTANT: Only protect the app bundle. Do NOT lock:
// - The daemon binary (prevents restarts/updates)
// - The LaunchDaemon plist (prevents launchctl management)
// - The config dir (the daemon needs to write status/history)

func lockFiles() {
    // Only lock the app bundle -- the most visible target for deletion
    runShell("chflags -R schg /Applications/FocusGuard.app 2>/dev/null")
}

func unlockFiles() {
    runShell("chflags -R noschg /Applications/FocusGuard.app 2>/dev/null")
}

// MARK: - Chrome DoH Policy

func enforceChromePolicy() {
    let prefsDir = FocusGuardConfig.chromePrefsDir
    let plistName = FocusGuardConfig.chromePlistName

    runShell("mkdir -p '\(prefsDir)'")
    runShell("defaults write '\(prefsDir)/\(plistName)' DnsOverHttpsMode -string 'off'")
    log("Chrome DoH policy set to off")
}

// MARK: - Blocked Domains File Management

func addDomain(_ domain: String) {
    let existing = readBlockedDomains()
    let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !cleaned.isEmpty else { return }

    if existing.contains(where: { $0.lowercased() == cleaned }) {
        log("Domain \(cleaned) already in blocklist")
        return
    }

    do {
        var contents = (try? String(contentsOfFile: blockedFile, encoding: .utf8)) ?? ""
        if !contents.hasSuffix("\n") { contents += "\n" }
        contents += cleaned + "\n"
        try contents.write(toFile: blockedFile, atomically: false, encoding: .utf8)
        log("Added domain: \(cleaned)")
    } catch {
        log("Failed to add domain: \(error)")
    }
}

func removeDomain(_ domain: String) {
    let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !cleaned.isEmpty else { return }

    do {
        let contents = try String(contentsOfFile: blockedFile, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed != cleaned
        }
        try filtered.joined(separator: "\n").write(toFile: blockedFile, atomically: false, encoding: .utf8)
        log("Removed domain: \(cleaned)")
    } catch {
        log("Failed to remove domain: \(error)")
    }
}

// MARK: - Core Enforcement

func enforce() {
    let config = readConfig()
    let domains = readBlockedDomains()
    let unlockTime = readUnlockRequestTime()
    let cooldownEnd = readCooldownEnd()
    let now = Date()
    let todayCount = unlocksToday()

    let effectiveDelay = currentUnlockDelay(baseDelay: config.unlockDelay)

    var currentStatus: BlockerStatus = .locked
    var shouldBlock = true
    var activeCooldownEnd: Date? = cooldownEnd

    // Check cooldown: if we're in an unlocked window, check if it expired
    if let endTime = cooldownEnd {
        if now >= endTime {
            log("Cooldown expired, auto-relocking")
            deleteUnlockFile()
            deleteCooldownFile()
            activeCooldownEnd = nil
            currentStatus = .locked
            shouldBlock = true
        } else {
            currentStatus = .unlocked
            shouldBlock = false
        }
    } else if let requestTime = unlockTime {
        let elapsed = now.timeIntervalSince(requestTime)
        if elapsed >= Double(effectiveDelay) {
            currentStatus = .unlocked
            shouldBlock = false
            let cooldownEndTime = now.addingTimeInterval(Double(config.cooldownDuration))
            writeCooldownEnd(cooldownEndTime)
            activeCooldownEnd = cooldownEndTime
            recordUnlock()
            log("Unlock delay elapsed - entering \(config.cooldownDuration)s cooldown window")
        } else {
            currentStatus = .unlockPending
            shouldBlock = true
        }
    }

    if shouldBlock {
        if !domains.isEmpty {
            writeBlocks(domains: domains)
            flushDNS()
        }
        lockFiles()
    } else {
        unlockFiles()
        removeBlocks()
        flushDNS()
    }

    // Write status
    let status = StatusInfo(
        status: currentStatus,
        blockedDomains: domains,
        unlockRequestTime: unlockTime,
        unlockDelay: effectiveDelay,
        lastEnforced: now,
        unlocksToday: todayCount,
        maxUnlocksPerDay: config.maxUnlocksPerDay,
        cooldownEndTime: activeCooldownEnd,
        cooldownDuration: config.cooldownDuration
    )
    writeStatus(status)
}

// MARK: - Command Processing

func processCommand() {
    guard FileManager.default.fileExists(atPath: commandFile) else { return }

    defer {
        try? FileManager.default.removeItem(atPath: commandFile)
    }

    guard let data = FileManager.default.contents(atPath: commandFile) else {
        log("Could not read command file")
        return
    }

    let message: CommandMessage
    do {
        message = try JSONDecoder().decode(CommandMessage.self, from: data)
    } catch {
        log("Failed to parse command: \(error)")
        return
    }

    log("Processing command: \(message.command.rawValue)")

    switch message.command {
    case .lock:
        deleteUnlockFile()
        deleteCooldownFile()
        enforce()

    case .unlock:
        let config = readConfig()
        let todayCount = unlocksToday()
        if todayCount >= config.maxUnlocksPerDay {
            log("Unlock DENIED - daily budget exhausted (\(todayCount)/\(config.maxUnlocksPerDay))")
        } else {
            writeUnlockFile()
            log("Unlock requested (\(todayCount + 1)/\(config.maxUnlocksPerDay) today)")
        }
        enforce()

    case .addDomain:
        if let domain = message.argument {
            addDomain(domain)
            enforce()
        }

    case .removeDomain:
        if let domain = message.argument {
            removeDomain(domain)
            enforce()
        }

    case .refresh:
        enforce()
    }
}

// MARK: - Main

// Log immediately so we know the daemon started
log("FocusGuard daemon v2 starting (PID: \(ProcessInfo.processInfo.processIdentifier))")

// Ensure config directory exists
do {
    try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
} catch {
    log("Warning: Could not create config dir: \(error)")
}

// Enforce Chrome DoH policy on startup
enforceChromePolicy()

// Run initial enforcement
log("Running initial enforcement...")
enforce()
log("Initial enforcement complete")

// Timer 1: Enforce blocks every 30 seconds
let enforceTimer = Timer(timeInterval: 30.0, repeats: true) { _ in
    enforce()
}

// Timer 2: Check for commands every 2 seconds
let commandTimer = Timer(timeInterval: 2.0, repeats: true) { _ in
    processCommand()
}

// Add timers to the run loop
let runLoop = RunLoop.current
runLoop.add(enforceTimer, forMode: .default)
runLoop.add(commandTimer, forMode: .default)

log("FocusGuard daemon running (enforce: 30s, commands: 2s)")

// Run forever
runLoop.run()
