import Foundation
import Darwin
import FocusGuardShared
import FocusGuardCore

/// The FocusGuard daemon state machine. All state mutation runs on a single
/// serial queue (timers + socket commands), so there are no data races.
final class Daemon {
    // Paths
    private let configDir = FocusGuardConfig.configDir
    private let blockedFile = FocusGuardConfig.blockedFile
    private let appBlockedFile = FocusGuardConfig.appBlockedFile
    private let unlockFile = FocusGuardConfig.unlockFile
    private let cooldownFile = FocusGuardConfig.cooldownFile
    private let historyFile = FocusGuardConfig.unlockHistoryFile
    private let sessionFile = FocusGuardConfig.sessionFile
    private let statusFile = FocusGuardConfig.statusFile

    // Collaborators
    let stateQueue = DispatchQueue(label: "com.focusguard.state")
    private let logger = DaemonLogger(path: FocusGuardConfig.daemonLogFile)
    private let stats: StatsStore
    private var socketServer: SocketServer!

    // In-memory state
    private var config: DaemonConfig
    private var lastScheduleActive = false
    private var lastShouldBlock = true
    private var lastBlockedApps: [String] = []
    private var enforceTimer: DispatchSourceTimer?
    private var appTimer: DispatchSourceTimer?
    private let cachedBootId: String
    private var deadlineTimer: DispatchSourceTimer?
    /// Last known presence of the always-on profiles (nil = not checked / not applicable).
    private var browserPolicyActive: Bool?
    private var dnsProfileActive: Bool?
    private var dnsCheckRunning = false
    private var lastDnsCheck = Date.distantPast
    private static let dnsCheckInterval: TimeInterval = 600

    init() {
        self.config = ConfigSchema.parse(data: FileManager.default.contents(atPath: FocusGuardConfig.configFile))
        self.cachedBootId = Daemon.bootId()
        self.stats = StatsStore(path: FocusGuardConfig.statsFile, today: Daemon.todayString(), log: { _ in })
    }

    func log(_ message: String) { logger.log(message) }

    // MARK: - Lifecycle

    func start() {
        log("FocusGuard daemon v\(FocusGuardConfig.daemonProtocolVersion) starting (PID \(getpid()))")
        ensureConfigDir()
        unlink(FocusGuardConfig.legacyCommandFile) // retire the old world-writable IPC file
        migrateConfigIfNeeded()
        verifyBrowserPolicy()
        verifyDnsProfile(force: true)

        socketServer = SocketServer(
            path: FocusGuardConfig.socketPath,
            stateQueue: stateQueue,
            log: { [weak self] in self?.log($0) },
            handler: { [weak self] msg in self?.handleCommand(msg) ?? CommandResponse(ok: false, error: .internalError) }
        )
        socketServer.start()

        stateQueue.sync { _ = self.enforce() }

        let et = DispatchSource.makeTimerSource(queue: stateQueue)
        et.schedule(deadline: .now() + 30, repeating: 30)
        et.setEventHandler { [weak self] in
            _ = self?.enforce()
            self?.verifyBrowserPolicy() // cheap file check; logs only on change
            self?.verifyDnsProfile()    // `profiles show` off-queue, every 10 min
        }
        et.resume()
        enforceTimer = et

        let interval = Double(config.appCheckInterval)
        let at = DispatchSource.makeTimerSource(queue: stateQueue)
        at.schedule(deadline: .now() + interval, repeating: interval)
        at.setEventHandler { [weak self] in self?.appCheckTick() }
        at.resume()
        appTimer = at

        log("Daemon running (enforce: 30s, apps: \(config.appCheckInterval)s, socket: \(FocusGuardConfig.socketPath))")
    }

    // MARK: - Enforcement

    @discardableResult
    func enforce() -> StatusInfo {
        config = ConfigSchema.parse(data: FileManager.default.contents(atPath: FocusGuardConfig.configFile))
        let userDomains = readBlockedDomains()
        // Always-on hardening: enforced in /etc/hosts even during an unlock window,
        // and deliberately kept OUT of status/sync so the list never surfaces.
        let alwaysDomains = config.extraBlocking ? ExtraBlocklist.domains : []
        let blockedApps = readBlockedApps()
        let enforcedApps = config.blockTor ? blockedApps + [FocusGuardConfig.torBrowserAppName] : blockedApps
        let now = Date()
        let nowMono = Daemon.monotonicNanos()
        let today = Daemon.todayString()

        // --- Focus session (hard lock, overrides everything) ---
        var sessionEnd: Date?
        if let session = readSessionInfo() {
            if isSessionActive(session, now: now, nowMono: nowMono) {
                sessionEnd = Date(timeIntervalSince1970: session.endWall)
            } else {
                deleteFile(sessionFile)
                stats.recordSessionCompleted(today: today, minutes: session.minutes)
                log("Focus session completed (\(session.minutes) min)")
            }
        }
        let sessionActive = sessionEnd != nil
        if sessionActive { deleteFile(unlockFile); deleteFile(cooldownFile) }

        // --- Schedule baseline ---
        let scheduleActive = ScheduleMath.isActive(config.schedules, at: now, calendar: .current)
        let scheduleRisingEdge = scheduleActive && !lastScheduleActive
        lastScheduleActive = scheduleActive
        if scheduleRisingEdge && !sessionActive {
            deleteFile(unlockFile); deleteFile(cooldownFile)
            log("Schedule window started; relocking")
        }

        // --- Determine status & blocking ---
        var status: BlockerStatus = .locked
        var shouldBlock = true
        var activeCooldownEnd: Date?
        var effectiveRequestTime: Date?
        var pendingDeadline: Date?

        if sessionActive {
            status = .focusSession
            shouldBlock = true
        } else {
            let unlockStamp = readUnlockStamp()
            let cooldownStamp = readCooldownStamp()
            let todayCount = currentUnlocksToday(now: now, nowMono: nowMono, today: today)
            let effectiveDelay = EscalationMath.currentDelay(base: config.unlockDelay, unlocksToday: todayCount)
            let wallNow = now.timeIntervalSince1970

            if let endStamp = cooldownStamp {
                if UnlockClock.windowExpired(end: endStamp, nowWall: wallNow, bootId: cachedBootId, nowMonotonic: nowMono) {
                    log("Cooldown expired, auto-relocking")
                    deleteFile(unlockFile); deleteFile(cooldownFile)
                    status = .locked; shouldBlock = true
                } else {
                    status = .unlocked; shouldBlock = false
                    activeCooldownEnd = Date(timeIntervalSince1970: UnlockClock.displayEnd(end: endStamp, nowWall: wallNow, bootId: cachedBootId, nowMonotonic: nowMono))
                }
            } else if let request = unlockStamp {
                let elapsed = UnlockClock.elapsed(since: request, nowWall: wallNow, bootId: cachedBootId, nowMonotonic: nowMono)
                if elapsed >= Double(effectiveDelay) {
                    status = .unlocked; shouldBlock = false
                    let opened = ClockStamp(wall: wallNow, bootId: cachedBootId, monotonic: nowMono)
                    let endStamp = UnlockClock.windowEnd(opened: opened, durationSeconds: config.cooldownDuration)
                    writeCooldownStamp(endStamp)
                    activeCooldownEnd = Date(timeIntervalSince1970: endStamp.wall)
                    recordUnlock(now: now, nowMono: nowMono, today: today)
                    stats.recordCompletedUnlock(today: today)
                    log("Unlock delay elapsed - entering \(config.cooldownDuration)s window")
                } else {
                    status = .unlockPending; shouldBlock = true
                    // Request time as the clocks we trust see it, so the app's countdown is honest.
                    effectiveRequestTime = now.addingTimeInterval(-max(0, elapsed))
                    pendingDeadline = now.addingTimeInterval(Double(effectiveDelay) - max(0, elapsed))
                }
            } else {
                // Baseline: always-on unless schedules exist and we're outside a window.
                let baselineLocked = config.schedules.isEmpty || scheduleActive
                status = baselineLocked ? .locked : .unlocked
                shouldBlock = baselineLocked
            }
        }

        applyHosts(userDomains: userDomains, alwaysDomains: alwaysDomains, shouldBlock: shouldBlock)

        // --- App blocking (only while effectively locked) ---
        if shouldBlock && !enforcedApps.isEmpty {
            stats.recordAppsKilled(AppBlocker.killBlockedApps(enforcedApps, log: { [weak self] in self?.log($0) }))
        }
        lastShouldBlock = shouldBlock
        lastBlockedApps = enforcedApps

        // Honesty signal: sites the installed browser profile still blocks that we are
        // NOT enforcing in /etc/hosts (removed-but-stale, or any site during an unlock
        // window). ExtraBlocklist is subtracted so the always-on list never surfaces.
        let liveBlocked = Set((shouldBlock ? userDomains : []) + alwaysDomains)
        let browserOnly = BrowserPolicyDiff.browserOnlyBlocked(
            installed: installedBrowserBlocklist(),
            liveBlocked: liveBlocked,
            extra: Set(ExtraBlocklist.domains)
        )

        // --- Status output ---
        let finalCount = currentUnlocksToday(now: now, nowMono: nowMono, today: today)
        let info = StatusInfo(
            status: status,
            blockedDomains: userDomains,
            unlockRequestTime: status == .unlockPending ? effectiveRequestTime : nil,
            unlockDelay: EscalationMath.currentDelay(base: config.unlockDelay, unlocksToday: finalCount),
            lastEnforced: now,
            unlocksToday: finalCount,
            maxUnlocksPerDay: config.maxUnlocksPerDay,
            cooldownEndTime: activeCooldownEnd,
            cooldownDuration: config.cooldownDuration,
            scheduleActive: scheduleActive,
            nextScheduleChange: ScheduleMath.nextTransition(config.schedules, after: now, calendar: .current),
            sessionEndTime: sessionEnd,
            blockedApps: blockedApps,
            schedules: config.schedules,
            stats: stats.summary(today: today),
            daemonVersion: FocusGuardConfig.daemonProtocolVersion,
            browserOnlyBlocked: browserOnly.isEmpty ? nil : browserOnly,
            missingProtections: missingProtections()
        )
        writeStatus(info)
        scheduleDeadlineTimer(pendingDeadline ?? activeCooldownEnd ?? sessionEnd)
        syncToCloud(domains: userDomains, locked: shouldBlock, cooldownEnd: activeCooldownEnd)
        return info
    }

    /// Writes the hosts block. `userDomains` are blocked only while locked;
    /// `alwaysDomains` (the always-on extra blocklist, `ExtraBlocklist`) are blocked
    /// regardless of lock state, so an earned unlock frees user domains only.
    /// Order preserved, deduped.
    private func applyHosts(userDomains: [String], alwaysDomains: [String], shouldBlock: Bool) {
        let current = HostsWriter.currentHosts()
        var seen = Set<String>()
        let effective = ((shouldBlock ? userDomains : []) + alwaysDomains)
            .filter { seen.insert($0).inserted }

        if !effective.isEmpty {
            let expected = HostsWriter.expectedHosts(domains: effective)
            if current != expected {
                HostsWriter.write(expected, log: { [weak self] in self?.log($0) })
                stats.recordHostsRewrite()
                flushDNS()
            }
        } else if current.contains(HostsWriter.markerStart) {
            HostsWriter.write(HostsWriter.cleanHosts(), log: { [weak self] in self?.log($0) })
            flushDNS()
        }

        if shouldBlock { lockFiles() } else { unlockFiles() }
    }

    private func appCheckTick() {
        guard lastShouldBlock, !lastBlockedApps.isEmpty else { return }
        stats.recordAppsKilled(AppBlocker.killBlockedApps(lastBlockedApps, log: { [weak self] in self?.log($0) }))
    }

    // MARK: - Command handling (runs on stateQueue via SocketServer)

    func handleCommand(_ msg: CommandMessage) -> CommandResponse {
        let current = enforce() // authoritative current state
        let sessionActive = current.status == .focusSession
        func ok() -> CommandResponse { CommandResponse(ok: true, status: enforce()) }
        func fail(_ e: CommandError) -> CommandResponse { CommandResponse(ok: false, error: e, status: current) }

        log("Command: \(msg.command.rawValue)")
        switch msg.command {
        case .getStatus:
            return CommandResponse(ok: true, status: current)
        case .refresh:
            return ok()
        case .lock:
            deleteFile(unlockFile); deleteFile(cooldownFile)
            return ok()
        case .cancelUnlock:
            guard current.status == .unlockPending else { return fail(.invalidArgument) }
            deleteFile(unlockFile)
            return ok()
        case .unlock:
            if sessionActive { return fail(.sessionActive) }
            // Only from the locked state: a second request must not restart the delay,
            // and a request inside an open window must not leave a stray unlock file.
            guard current.status == .locked else { return fail(.invalidArgument) }
            let today = Daemon.todayString()
            let count = currentUnlocksToday(now: Date(), nowMono: Daemon.monotonicNanos(), today: today)
            if count >= config.maxUnlocksPerDay {
                stats.recordDeniedUnlock()
                log("Unlock DENIED - budget exhausted (\(count)/\(config.maxUnlocksPerDay))")
                return fail(.budgetExhausted)
            }
            writeUnlockFile()
            stats.recordUnlockRequest()
            log("Unlock requested (\(count + 1)/\(config.maxUnlocksPerDay) today)")
            return ok()
        case .startSession:
            guard let raw = msg.argument, let mins = Int(raw) else { return fail(.invalidArgument) }
            let clamped = min(FocusGuardConfig.maxSessionMinutes, max(FocusGuardConfig.minSessionMinutes, mins))
            startSession(minutes: clamped)
            return ok()
        case .addDomain:
            guard let arg = msg.argument else { return fail(.invalidArgument) }
            switch DomainValidation.clean(arg) {
            case .success(let d): addLine(d, to: blockedFile); return ok()
            case .failure(let e): return fail(e.commandError)
            }
        case .addDomains:
            guard let arg = msg.argument else { return fail(.invalidArgument) }
            var added = 0
            for raw in arg.components(separatedBy: "\n") {
                if case .success(let d) = DomainValidation.clean(raw) { addLine(d, to: blockedFile); added += 1 }
            }
            return added > 0 ? ok() : fail(.invalidDomain)
        case .removeDomain, .removeDomains:
            guard earnedUnlock(current) else { return fail(.lockedState) }
            if sessionActive { return fail(.sessionActive) }
            guard let arg = msg.argument else { return fail(.invalidArgument) }
            let list = arg.components(separatedBy: "\n").map { DomainValidation.normalize($0) }.filter { !$0.isEmpty }
            removeLines(list, from: blockedFile)
            return ok()
        case .addApp:
            guard let arg = msg.argument else { return fail(.invalidArgument) }
            let name = AppMatchRules.normalize(arg)
            guard AppMatchRules.isValidAppName(name) else { return fail(.invalidApp) }
            addLine(name, to: appBlockedFile)
            return ok()
        case .removeApp:
            guard earnedUnlock(current) else { return fail(.lockedState) }
            if sessionActive { return fail(.sessionActive) }
            guard let arg = msg.argument else { return fail(.invalidArgument) }
            removeLines([AppMatchRules.normalize(arg)], from: appBlockedFile)
            return ok()
        case .addSchedule:
            guard let arg = msg.argument, let data = arg.data(using: .utf8),
                  let sched = try? JSONDecoder().decode(Schedule.self, from: data),
                  ScheduleMath.isValid(sched) else { return fail(.invalidArgument) }
            mutateSchedules { $0.removeAll { $0.id == sched.id }; $0.append(sched) }
            return ok()
        case .removeSchedule:
            guard earnedUnlock(current) else { return fail(.lockedState) }
            guard let id = msg.argument else { return fail(.invalidArgument) }
            mutateSchedules { $0.removeAll { $0.id == id } }
            return ok()
        }
    }

    // MARK: - Focus session

    private struct SessionInfo: Codable {
        var startWall: Double
        var endWall: Double
        var bootId: String
        var endMonotonic: UInt64
        var minutes: Int
    }

    private func startSession(minutes: Int) {
        let now = Date().timeIntervalSince1970
        let info = SessionInfo(
            startWall: now,
            endWall: now + Double(minutes * 60),
            bootId: cachedBootId,
            endMonotonic: Daemon.monotonicNanos() + UInt64(minutes) * 60 * 1_000_000_000,
            minutes: minutes
        )
        if let data = try? JSONEncoder().encode(info) {
            AtomicFile.write(data, to: sessionFile, mode: 0o644, owner: 0, group: 0)
        }
        deleteFile(unlockFile); deleteFile(cooldownFile)
        stats.recordSessionStarted(today: Daemon.todayString())
        log("Focus session started: \(minutes) min (uncancellable)")
    }

    private func readSessionInfo() -> SessionInfo? {
        guard let data = FileManager.default.contents(atPath: sessionFile),
              let info = try? JSONDecoder().decode(SessionInfo.self, from: data) else { return nil }
        return info
    }

    /// Active if the wall clock OR the monotonic clock says so (whichever is
    /// later). Clock rewinds can only extend a session, never shorten it.
    private func isSessionActive(_ s: SessionInfo, now: Date, nowMono: UInt64) -> Bool {
        let wallActive = now.timeIntervalSince1970 < s.endWall
        let monoActive = s.bootId == cachedBootId && nowMono < s.endMonotonic
        return wallActive || monoActive
    }

    // MARK: - Schedules / config

    private func mutateSchedules(_ transform: (inout [Schedule]) -> Void) {
        var schedules = config.schedules
        transform(&schedules)
        config.schedules = schedules.filter { ScheduleMath.isValid($0) }
        saveConfig()
    }

    private func saveConfig() {
        config.version = FocusGuardConfig.currentConfigVersion
        if let data = ConfigSchema.serialize(config) {
            AtomicFile.write(data, to: FocusGuardConfig.configFile, mode: 0o644, owner: 0, group: 0)
        }
    }

    private func migrateConfigIfNeeded() {
        if config.version < FocusGuardConfig.currentConfigVersion {
            log("Migrating config v\(config.version) -> v\(FocusGuardConfig.currentConfigVersion)")
            saveConfig()
        }
    }

    private func ensureConfigDir() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }

    // MARK: - Blocklist files (domains + apps)

    private func readBlockedDomains() -> [String] {
        guard let contents = try? String(contentsOfFile: blockedFile, encoding: .utf8) else { return [] }
        var valid: [String] = []
        for raw in contents.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            switch DomainValidation.validate(line.lowercased()) {
            case .success(let d): valid.append(d)
            case .failure(let e): log("Skipping invalid blocklist entry '\(line)': \(e)")
            }
        }
        return valid
    }

    private func readBlockedApps() -> [String] {
        guard let contents = try? String(contentsOfFile: appBlockedFile, encoding: .utf8) else { return [] }
        return contents.components(separatedBy: .newlines)
            .map { AppMatchRules.normalize($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && AppMatchRules.isValidAppName($0) }
    }

    private func addLine(_ value: String, to file: String) {
        var existing = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        let present = existing.components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == value.lowercased() }
        guard !present else { log("\(value) already present in \(file)"); return }
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        existing += value + "\n"
        AtomicFile.writeString(existing, to: file, mode: 0o644, owner: 0, group: 0)
        log("Added '\(value)' to \(file)")
    }

    private func removeLines(_ values: [String], from file: String) {
        guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else { return }
        let toRemove = Set(values.map { $0.lowercased() })
        let filtered = contents.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.isEmpty || trimmed.hasPrefix("#") || !toRemove.contains(trimmed)
        }
        AtomicFile.writeString(filtered.joined(separator: "\n"), to: file, mode: 0o644, owner: 0, group: 0)
        log("Removed \(toRemove.count) entry(ies) from \(file)")
    }

    // MARK: - Unlock files / history

    private func readUnlockStamp() -> ClockStamp? {
        guard let data = FileManager.default.contents(atPath: unlockFile) else { return nil }
        return ClockStamp.decode(data)
    }

    private func writeUnlockFile() {
        let stamp = ClockStamp(wall: Date().timeIntervalSince1970, bootId: cachedBootId, monotonic: Daemon.monotonicNanos())
        if let data = try? JSONEncoder().encode(stamp) {
            AtomicFile.write(data, to: unlockFile, mode: 0o644, owner: 0, group: 0)
        }
    }

    private func readCooldownStamp() -> ClockStamp? {
        guard let data = FileManager.default.contents(atPath: cooldownFile) else { return nil }
        return ClockStamp.decode(data)
    }

    private func writeCooldownStamp(_ stamp: ClockStamp) {
        if let data = try? JSONEncoder().encode(stamp) {
            AtomicFile.write(data, to: cooldownFile, mode: 0o644, owner: 0, group: 0)
        }
    }

    /// Removals need an unlock the user actually waited for, not just "unlocked"
    /// (outside a schedule window the baseline is unlocked with no delay served).
    private func earnedUnlock(_ info: StatusInfo) -> Bool {
        info.status == .unlocked && info.cooldownEndTime != nil
    }

    /// Re-evaluates exactly when the next deadline passes, so unlock and relock
    /// happen on time instead of up to 30 s late. The 30 s tick re-arms it.
    private func scheduleDeadlineTimer(_ deadline: Date?) {
        deadlineTimer?.cancel()
        deadlineTimer = nil
        guard let deadline else { return }
        let delay = deadline.timeIntervalSinceNow + 0.5
        guard delay > 0, delay <= 31 else { return }
        let t = DispatchSource.makeTimerSource(queue: stateQueue)
        t.schedule(deadline: .now() + delay)
        t.setEventHandler { [weak self] in _ = self?.enforce() }
        t.resume()
        deadlineTimer = t
    }

    private struct UnlockHistory: Codable { var entries: [UnlockRecord] }

    private func readHistory() -> [UnlockRecord] {
        guard let data = FileManager.default.contents(atPath: historyFile),
              let history = try? JSONDecoder().decode(UnlockHistory.self, from: data) else { return [] }
        return history.entries
    }

    private func currentUnlocksToday(now: Date, nowMono: UInt64, today: String) -> Int {
        EscalationMath.unlocksToday(records: readHistory(), today: today, currentBootId: cachedBootId, nowMonotonic: nowMono)
    }

    private func recordUnlock(now: Date, nowMono: UInt64, today: String) {
        var entries = readHistory()
        entries.append(UnlockRecord(date: today, timestamp: now.timeIntervalSince1970, bootId: cachedBootId, monotonic: nowMono))
        entries = EscalationMath.prune(records: entries, now: now.timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(UnlockHistory(entries: entries)) {
            AtomicFile.write(data, to: historyFile, mode: 0o644, owner: 0, group: 0)
        }
    }

    // MARK: - Status output

    private func writeStatus(_ status: StatusInfo) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(status) {
            AtomicFile.write(data, to: statusFile, mode: 0o644, owner: 0, group: 0)
        }
    }

    // MARK: - File protection

    private func lockFiles() {
        runShell("chflags -R schg /Applications/FocusGuard.app 2>/dev/null")
    }

    private func unlockFiles() {
        runShell("chflags -R noschg /Applications/FocusGuard.app 2>/dev/null")
    }

    // MARK: - Browser policy (delivered via configuration profile)

    /// Browser enterprise policy (Brave `URLBlocklist` + Chrome/Brave
    /// `DnsOverHttpsMode=off`) can only come from a configuration profile on modern
    /// macOS -- `/Library/Managed Preferences` is sourced solely from profiles, so a
    /// daemon `defaults write` there is a silent no-op (and could fight the profile).
    /// We therefore only VERIFY the profile is present: the OS materialises the
    /// managed plist once the profile is installed. `URLBlocklist` blocks the always-on
    /// list in every Brave window INCLUDING Tor windows (enforced pre-network), so
    /// Brave's Tor feature stays usable. Build/refresh the populated profile with
    /// Scripts/make-browser-profile.sh, then install it.
    private func verifyBrowserPolicy() {
        guard config.blockTor else { browserPolicyActive = nil; return }
        let bravePolicyPlist = "\(FocusGuardConfig.chromePrefsDir)/\(FocusGuardConfig.bravePlistName).plist"
        let installed = FileManager.default.fileExists(atPath: bravePolicyPlist)
        if installed != browserPolicyActive {
            log(installed
                ? "Browser policy profile active (URLBlocklist + DoH off)"
                : "Browser policy profile NOT installed -- blocklist not enforced in Brave Tor windows (run Scripts/make-browser-profile.sh and install it)")
            browserPolicyActive = installed
        }
    }

    /// Always-on protections currently missing, for the app's warning banner.
    private func missingProtections() -> [String]? {
        var missing: [String] = []
        if browserPolicyActive == false { missing.append("browserPolicy") }
        if dnsProfileActive == false { missing.append("categoryDNS") }
        return missing.isEmpty ? nil : missing
    }

    /// The URLBlocklist macOS materialised from the installed browser policy profile
    /// (`/Library/Managed Preferences/<browser>.plist`) — what the browser ACTUALLY
    /// enforces, independent of FocusGuard's lock state. Empty when no profile is
    /// installed. Read-only; never written.
    private func installedBrowserBlocklist() -> Set<String> {
        var result = Set<String>()
        for name in [FocusGuardConfig.bravePlistName, FocusGuardConfig.chromePlistName] {
            let path = "\(FocusGuardConfig.chromePrefsDir)/\(name).plist"
            guard let dict = NSDictionary(contentsOfFile: path),
                  let list = dict["URLBlocklist"] as? [String] else { continue }
            for entry in list {
                let d = entry.trimmingCharacters(in: .whitespaces).lowercased()
                if !d.isEmpty { result.insert(d) }
            }
        }
        return result
    }

    // MARK: - Category DNS profile (Cloudflare 1.1.1.1 for Families)

    /// The Mac routes system DNS through Cloudflare 1.1.1.1 for Families via a managed DoH
    /// configuration profile (Resources/FocusGuard-Mac-DNS.mobileconfig), blocking the whole
    /// adult-content category + malware system-wide, UNDER the /etc/hosts list. Like the
    /// browser policy, the daemon can only VERIFY it -- a profile cannot be installed without
    /// user approval -- so we check that the Families resolver is actually the active system
    /// DNS via `scutil --dns`. Gated on extraBlocking (same adult-blocking intent). Log-only
    /// nudge; it never weakens anything.
    private func verifyDnsProfile(force: Bool = false) {
        guard config.extraBlocking else { dnsProfileActive = nil; return }
        guard !dnsCheckRunning, force || Date().timeIntervalSince(lastDnsCheck) >= Daemon.dnsCheckInterval else { return }
        dnsCheckRunning = true
        lastDnsCheck = Date()
        // The daemon is root, so it lists installed configuration profiles and matches ours by
        // identifier (`scutil --dns` and `dig` cannot see a profile-delivered DoH resolver).
        // `profiles show` can take seconds; run it off the state queue so socket
        // commands never wait on it (they time out client-side after 6 s).
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let active = self.runShellOutput("/usr/bin/profiles show 2>/dev/null").contains(FocusGuardConfig.dnsProfileIdentifier)
            self.stateQueue.async {
                self.dnsCheckRunning = false
                if active != self.dnsProfileActive {
                    self.log(active
                        ? "Category-DNS profile active (Cloudflare Families: adult + malware, system-wide)"
                        : "Category-DNS profile NOT active -- adult category not blocked system-wide (install Resources/FocusGuard-Mac-DNS.mobileconfig)")
                    self.dnsProfileActive = active
                }
            }
        }
    }

    // MARK: - Cloud sync (fire-and-forget, unchanged behavior)

    private var lastSyncHash = ""

    private func syncToCloud(domains: [String], locked: Bool, cooldownEnd: Date?) {
        guard let urlStr = config.workerUrl, let apiKey = config.workerApiKey,
              let url = URL(string: "\(urlStr)/api/sync") else { return }
        let cooldownMs = cooldownEnd.map { Int($0.timeIntervalSince1970 * 1000) }
        let hash = "\(domains.sorted().joined())-\(locked)-\(cooldownMs ?? 0)"
        guard hash != lastSyncHash else { return }
        lastSyncHash = hash

        var body: [String: Any] = ["domains": domains, "locked": locked]
        if let ms = cooldownMs { body["cooldownEnd"] = ms }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if error != nil { self?.stateQueue.async { self?.lastSyncHash = "" } }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                self?.stateQueue.async { self?.lastSyncHash = "" }
            }
        }.resume()
    }

    // MARK: - Shell + system helpers

    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() }
        catch { log("Failed to run: \(command) - \(error)") }
    }

    /// Like runShell, but captures and returns stdout. For small read-only system queries
    /// (e.g. `scutil --dns`); output fits the pipe buffer so read-then-wait cannot deadlock.
    private func runShellOutput(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            log("Failed to run: \(command) - \(error)")
            return ""
        }
    }

    private func flushDNS() {
        runShell("dscacheutil -flushcache")
        runShell("killall -HUP mDNSResponder")
    }

    private func deleteFile(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Static system helpers

    static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    static func monotonicNanos() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }

    static func bootId() -> String {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            return "\(tv.tv_sec).\(tv.tv_usec)"
        }
        return "unknown"
    }
}
