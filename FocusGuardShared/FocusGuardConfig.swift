import Foundation

/// Shared constants and configuration between the menu bar app and daemon
public enum FocusGuardConfig {
    public static let configDir = "/etc/focusguard"
    public static let blockedFile = "\(configDir)/blocked.txt"
    public static let appBlockedFile = "\(configDir)/appBlocked.txt"
    public static let configFile = "\(configDir)/config.json"
    public static let unlockFile = "\(configDir)/.unlock_requested"
    public static let statusFile = "\(configDir)/.status"
    public static let statsFile = "\(configDir)/stats.json"
    public static let sessionFile = "\(configDir)/.session"
    public static let cooldownFile = "\(configDir)/.cooldown_end"
    public static let unlockHistoryFile = "\(configDir)/.unlock_history"
    public static let hostsFile = "/etc/hosts"
    public static let lockMarkerStart = "# FOCUSGUARD-START"
    public static let lockMarkerEnd = "# FOCUSGUARD-END"

    /// Unix domain socket for command IPC (replaces the old world-writable
    /// /tmp command file). `/var/run` is cleared each boot, so no stale socket.
    public static let socketPath = "/var/run/focusguard.sock"
    /// Deprecated world-writable command file. Kept only so the daemon can
    /// remove a stale copy on startup; never written by the current app.
    public static let legacyCommandFile = "/tmp/focusguard.command"

    public static let daemonLabel = "com.focusguard.blocker"
    public static let daemonLogFile = "/var/log/focusguard.log"
    public static let launchdLogFile = "/var/log/focusguard.launchd.log"

    public static let defaultUnlockDelay: Int = 1200 // 20 minutes
    public static let defaultMaxUnlocksPerDay: Int = 2
    public static let defaultCooldownDuration: Int = 900 // 15 minutes
    public static let defaultAppCheckInterval: Int = 10 // seconds
    public static let currentConfigVersion: Int = 3
    /// Bumped whenever the app<->daemon contract changes. Surfaced in StatusInfo
    /// so the app can warn when it is talking to an out-of-date daemon.
    public static let daemonProtocolVersion: Int = 2

    public static let minSessionMinutes: Int = 5
    public static let maxSessionMinutes: Int = 480

    public static let chromePrefsDir = "/Library/Managed Preferences"
    public static let chromePlistName = "com.google.Chrome"
    public static let bravePlistName = "com.brave.Browser"

    /// App-bundle name (without ".app") force-killed while Tor blocking is on.
    public static let torBrowserAppName = "Tor Browser"

    /// Always-on hardening defaults (see DaemonConfig.extraBlocking / blockTor).
    public static let defaultExtraBlocking = true
    public static let defaultBlockTor = true
}

/// The current state of the blocker
public enum BlockerStatus: String, Codable, Sendable {
    case locked
    case unlockPending
    case unlocked
    /// Hard-locked focus session (Pomodoro). Cannot be unlocked until it ends.
    case focusSession
}

/// Aggregate stats surfaced to the UI (computed by the daemon from stats.json)
public struct StatsSummary: Codable, Equatable, Sendable {
    public var completedUnlocks: Int
    public var sessionsCompleted: Int
    public var currentStreakDays: Int
    public var bestStreakDays: Int
    public var unlockRequests: Int
    public var deniedUnlocks: Int
    public var focusMinutesToday: Int

    public init(
        completedUnlocks: Int = 0,
        sessionsCompleted: Int = 0,
        currentStreakDays: Int = 0,
        bestStreakDays: Int = 0,
        unlockRequests: Int = 0,
        deniedUnlocks: Int = 0,
        focusMinutesToday: Int = 0
    ) {
        self.completedUnlocks = completedUnlocks
        self.sessionsCompleted = sessionsCompleted
        self.currentStreakDays = currentStreakDays
        self.bestStreakDays = bestStreakDays
        self.unlockRequests = unlockRequests
        self.deniedUnlocks = deniedUnlocks
        self.focusMinutesToday = focusMinutesToday
    }
}

/// A recurring auto-lock window. Days use ISO weekday numbers (1 = Monday ... 7 = Sunday).
/// `start`/`end` are "HH:mm" local time. If `end <= start` the window spans midnight.
public struct Schedule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var days: Set<Int>
    public var start: String
    public var end: String

    public init(id: String, days: Set<Int>, start: String, end: String) {
        self.id = id
        self.days = days
        self.start = start
        self.end = end
    }

    /// Human label e.g. "Mon–Fri · 09:00–17:30"
    public var summary: String {
        let names = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let sorted = days.sorted()
        let dayPart: String
        if sorted == [1, 2, 3, 4, 5] {
            dayPart = "Mon–Fri"
        } else if sorted == [6, 7] {
            dayPart = "Weekends"
        } else if sorted == [1, 2, 3, 4, 5, 6, 7] {
            dayPart = "Every day"
        } else {
            dayPart = sorted.map { names[$0] }.joined(separator: ", ")
        }
        return "\(dayPart) · \(start)–\(end)"
    }
}

/// Status info written by daemon, read by app.
/// All fields added after v1 are optional so old and new builds stay
/// Codable-compatible in both directions.
public struct StatusInfo: Codable, Sendable {
    public var status: BlockerStatus
    public var blockedDomains: [String]
    public var unlockRequestTime: Date?
    public var unlockDelay: Int
    public var lastEnforced: Date?
    public var unlocksToday: Int
    public var maxUnlocksPerDay: Int
    public var cooldownEndTime: Date?
    public var cooldownDuration: Int

    // v2 additions (all optional for backward/forward compatibility)
    public var scheduleActive: Bool?
    public var nextScheduleChange: Date?
    public var sessionEndTime: Date?
    public var blockedApps: [String]?
    public var schedules: [Schedule]?
    public var stats: StatsSummary?
    public var daemonVersion: Int?

    public init(
        status: BlockerStatus = .locked,
        blockedDomains: [String] = [],
        unlockRequestTime: Date? = nil,
        unlockDelay: Int = FocusGuardConfig.defaultUnlockDelay,
        lastEnforced: Date? = nil,
        unlocksToday: Int = 0,
        maxUnlocksPerDay: Int = FocusGuardConfig.defaultMaxUnlocksPerDay,
        cooldownEndTime: Date? = nil,
        cooldownDuration: Int = FocusGuardConfig.defaultCooldownDuration,
        scheduleActive: Bool? = nil,
        nextScheduleChange: Date? = nil,
        sessionEndTime: Date? = nil,
        blockedApps: [String]? = nil,
        schedules: [Schedule]? = nil,
        stats: StatsSummary? = nil,
        daemonVersion: Int? = nil
    ) {
        self.status = status
        self.blockedDomains = blockedDomains
        self.unlockRequestTime = unlockRequestTime
        self.unlockDelay = unlockDelay
        self.lastEnforced = lastEnforced
        self.unlocksToday = unlocksToday
        self.maxUnlocksPerDay = maxUnlocksPerDay
        self.cooldownEndTime = cooldownEndTime
        self.cooldownDuration = cooldownDuration
        self.scheduleActive = scheduleActive
        self.nextScheduleChange = nextScheduleChange
        self.sessionEndTime = sessionEndTime
        self.blockedApps = blockedApps
        self.schedules = schedules
        self.stats = stats
        self.daemonVersion = daemonVersion
    }

    /// Seconds remaining until unlock takes effect
    public var unlockSecondsRemaining: Int? {
        guard let requestTime = unlockRequestTime else { return nil }
        let elapsed = Int(Date().timeIntervalSince(requestTime))
        let remaining = unlockDelay - elapsed
        return remaining > 0 ? remaining : 0
    }

    /// Seconds remaining in cooldown (unlocked window)
    public var cooldownSecondsRemaining: Int? {
        guard let endTime = cooldownEndTime else { return nil }
        let remaining = Int(endTime.timeIntervalSince(Date()))
        return remaining > 0 ? remaining : 0
    }

    /// Seconds remaining in an active focus session
    public var sessionSecondsRemaining: Int? {
        guard let endTime = sessionEndTime else { return nil }
        let remaining = Int(endTime.timeIntervalSince(Date()))
        return remaining > 0 ? remaining : 0
    }

    /// How many unlocks remain today
    public var unlocksRemaining: Int {
        max(0, maxUnlocksPerDay - unlocksToday)
    }

    /// Whether the daily budget is exhausted
    public var budgetExhausted: Bool {
        unlocksToday >= maxUnlocksPerDay
    }
}

/// Commands the app can send to the daemon over the Unix socket.
public enum DaemonCommand: String, Codable, Sendable {
    case lock
    case unlock
    case cancelUnlock
    case getStatus
    case startSession // argument = minutes (String)
    case addDomain
    case addDomains   // batch: argument is newline-separated domain list
    case removeDomain
    case removeDomains // batch: argument is newline-separated domain list
    case addApp        // argument = app name (e.g. "Steam")
    case removeApp
    case addSchedule   // argument = JSON-encoded Schedule
    case removeSchedule // argument = schedule id
    case refresh
}

public struct CommandMessage: Codable, Sendable {
    public var command: DaemonCommand
    public var argument: String?

    public init(command: DaemonCommand, argument: String? = nil) {
        self.command = command
        self.argument = argument
    }
}

/// Stable error codes returned by the daemon in a CommandResponse.
public enum CommandError: String, Codable, Sendable {
    case unauthorized
    case budgetExhausted = "budget_exhausted"
    case lockedState = "locked_state"
    case invalidDomain = "invalid_domain"
    case reservedDomain = "reserved_domain"
    case invalidApp = "invalid_app"
    case sessionActive = "session_active"
    case invalidArgument = "invalid_argument"
    case unknownCommand = "unknown_command"
    case internalError = "internal_error"

    /// Short, human-readable message for the UI.
    public var message: String {
        switch self {
        case .unauthorized: return "Not authorized"
        case .budgetExhausted: return "No unlocks left today"
        case .lockedState: return "Only available while unlocked"
        case .invalidDomain: return "That doesn't look like a valid domain"
        case .reservedDomain: return "That domain is protected and can't be blocked"
        case .invalidApp: return "That app name isn't valid"
        case .sessionActive: return "A focus session is running"
        case .invalidArgument: return "Invalid request"
        case .unknownCommand: return "Unsupported command"
        case .internalError: return "Something went wrong"
        }
    }
}

/// The daemon's reply to a command. `status` carries the fresh post-command
/// StatusInfo and doubles as the acknowledgement.
public struct CommandResponse: Codable, Sendable {
    public var ok: Bool
    public var error: CommandError?
    public var status: StatusInfo?

    public init(ok: Bool, error: CommandError? = nil, status: StatusInfo? = nil) {
        self.ok = ok
        self.error = error
        self.status = status
    }
}
