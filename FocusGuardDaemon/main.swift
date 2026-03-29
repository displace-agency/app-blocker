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
    FileHandle.standardError.write(Data("[\(timestamp)] \(message)\n".utf8))
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
    unlockConfigDir()
    defer { relockConfigDir() }
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
    let delay = baseDelay * multiplier
    log("Escalated delay: \(baseDelay)s * 2^\(count) = \(delay)s")
    return delay
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
    unlockConfigDir()
    defer { relockConfigDir() }
    if let data = try? JSONEncoder().encode(date.timeIntervalSince1970) {
        FileManager.default.createFile(atPath: cooldownFile, contents: data)
        log("Cooldown set: auto-relock at \(date)")
    }
}

func deleteCooldownFile() {
    unlockConfigDir()
    defer { relockConfigDir() }
    try? FileManager.default.removeItem(atPath: cooldownFile)
}

func readBlockedDomains() -> [String] {
    guard let contents = try? String(contentsOfFile: blockedFile, encoding: .utf8) else {
        log("Could not read \(blockedFile)")
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
    log("DNS cache flushed")
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
        return ""
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

    // Remove trailing empty lines that accumulate
    while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
        result.removeLast()
    }

    return result.joined(separator: "\n")
}

func writeBlocks(domains: [String]) {
    let clean = readHostsWithoutBlock()
    let block = buildBlockEntries(for: domains)
    let final = clean + "\n\n" + block + "\n"

    do {
        try final.write(toFile: hostsFile, atomically: true, encoding: .utf8)
        log("Wrote \(domains.count) domains to /etc/hosts")
    } catch {
        log("Failed to write \(hostsFile): \(error)")
    }
}

func removeBlocks() {
    let clean = readHostsWithoutBlock()
    let final = clean + "\n"

    do {
        try final.write(toFile: hostsFile, atomically: true, encoding: .utf8)
        log("Removed all block entries from /etc/hosts")
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
    unlockConfigDir()
    defer { relockConfigDir() }
    let timestamp = Date().timeIntervalSince1970
    if let data = try? JSONEncoder().encode(timestamp) {
        FileManager.default.createFile(atPath: unlockFile, contents: data)
        log("Created unlock request file")
    }
}

func deleteUnlockFile() {
    unlockConfigDir()
    defer { relockConfigDir() }
    try? FileManager.default.removeItem(atPath: unlockFile)
    log("Deleted unlock request file")
}

// MARK: - Status Reporting

func writeStatus(_ status: StatusInfo) {
    unlockConfigDir()
    defer { relockConfigDir() }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted

    do {
        let data = try encoder.encode(status)
        try data.write(to: URL(fileURLWithPath: statusFile))
    } catch {
        log("Failed to write status: \(error)")
    }
}

// MARK: - File Protection (immutable flags)

/// Set system immutable flag on critical files so they can't be deleted
func lockFiles() {
    let paths = [
        "/Applications/FocusGuard.app",
        "/usr/local/bin/focusguard-daemon",
        "/Library/LaunchDaemons/com.focusguard.blocker.plist",
        "/etc/focusguard",
    ]
    for path in paths {
        runShell("chflags -R schg '\(path)' 2>/dev/null")
    }
    log("Files locked (immutable)")
}

/// Remove immutable flags so files can be modified/deleted
func unlockFiles() {
    let paths = [
        "/Applications/FocusGuard.app",
        "/usr/local/bin/focusguard-daemon",
        "/Library/LaunchDaemons/com.focusguard.blocker.plist",
        "/etc/focusguard",
    ]
    for path in paths {
        runShell("chflags -R noschg '\(path)' 2>/dev/null")
    }
    log("Files unlocked (mutable)")
}

// MARK: - Chrome DoH Policy

func enforceChromePolicy() {
    let prefsDir = FocusGuardConfig.chromePrefsDir
    let plistName = FocusGuardConfig.chromePlistName

    // Ensure directory exists
    runShell("mkdir -p '\(prefsDir)'")

    // Disable DNS-over-HTTPS so /etc/hosts blocks take effect in Chrome
    runShell("defaults write '\(prefsDir)/\(plistName)' DnsOverHttpsMode -string 'off'")
    log("Chrome DoH policy set to off")
}

// MARK: - Blocked Domains File Management

func unlockConfigDir() {
    runShell("chflags -R noschg '\(configDir)' 2>/dev/null")
}

func relockConfigDir() {
    runShell("chflags -R schg '\(configDir)' 2>/dev/null")
}

func addDomain(_ domain: String) {
    unlockConfigDir()
    defer { relockConfigDir() }
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
        try contents.write(toFile: blockedFile, atomically: true, encoding: .utf8)
        log("Added domain: \(cleaned)")
    } catch {
        log("Failed to add domain: \(error)")
    }
}

func removeDomain(_ domain: String) {
    unlockConfigDir()
    defer { relockConfigDir() }
    let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !cleaned.isEmpty else { return }

    do {
        let contents = try String(contentsOfFile: blockedFile, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed != cleaned
        }
        try filtered.joined(separator: "\n").write(toFile: blockedFile, atomically: true, encoding: .utf8)
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

    // Calculate the escalated delay for the current unlock attempt
    let effectiveDelay = currentUnlockDelay(baseDelay: config.unlockDelay)

    var currentStatus: BlockerStatus = .locked
    var shouldBlock = true
    var activeCooldownEnd: Date? = cooldownEnd

    // Check cooldown: if we're in an unlocked window, check if it expired
    if let endTime = cooldownEnd {
        if now >= endTime {
            // Cooldown expired -- auto-relock
            log("Cooldown expired, auto-relocking")
            deleteUnlockFile()
            deleteCooldownFile()
            activeCooldownEnd = nil
            currentStatus = .locked
            shouldBlock = true
        } else {
            // Still in cooldown window (unlocked)
            currentStatus = .unlocked
            shouldBlock = false
            let remaining = Int(endTime.timeIntervalSince(now))
            log("Unlocked - auto-relock in \(remaining)s")
        }
    } else if let requestTime = unlockTime {
        let elapsed = now.timeIntervalSince(requestTime)
        if elapsed >= Double(effectiveDelay) {
            // Unlock delay passed -- enter cooldown window
            currentStatus = .unlocked
            shouldBlock = false
            let cooldownEndTime = now.addingTimeInterval(Double(config.cooldownDuration))
            writeCooldownEnd(cooldownEndTime)
            activeCooldownEnd = cooldownEndTime
            recordUnlock()
            log("Unlock delay elapsed - entering \(config.cooldownDuration)s cooldown window")
        } else {
            // Still waiting for unlock delay
            currentStatus = .unlockPending
            shouldBlock = true
            let remaining = effectiveDelay - Int(elapsed)
            log("Unlock pending - \(remaining)s remaining (escalated delay: \(effectiveDelay)s)")
        }
    }

    if shouldBlock {
        if domains.isEmpty {
            log("No domains to block")
        } else {
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
            // Don't create unlock file -- budget is spent
        } else {
            writeUnlockFile()
            log("Unlock requested (\(todayCount + 1)/\(config.maxUnlocksPerDay) today)")
        }
        enforce()

    case .addDomain:
        if let domain = message.argument {
            addDomain(domain)
            enforce()
        } else {
            log("addDomain command missing argument")
        }

    case .removeDomain:
        if let domain = message.argument {
            removeDomain(domain)
            enforce()
        } else {
            log("removeDomain command missing argument")
        }

    case .refresh:
        enforce()
    }
}

// MARK: - Main

log("FocusGuard daemon starting")

// Ensure config directory exists
runShell("mkdir -p '\(configDir)'")

// Enforce Chrome DoH policy on startup
enforceChromePolicy()

// Run initial enforcement immediately
enforce()

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
