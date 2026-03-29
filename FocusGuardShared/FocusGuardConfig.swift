import Foundation

/// Shared constants and configuration between the menu bar app and daemon
public enum FocusGuardConfig {
    public static let configDir = "/etc/focusguard"
    public static let blockedFile = "\(configDir)/blocked.txt"
    public static let configFile = "\(configDir)/config.json"
    public static let unlockFile = "\(configDir)/.unlock_requested"
    public static let statusFile = "\(configDir)/.status"
    public static let hostsFile = "/etc/hosts"
    public static let lockMarkerStart = "# FOCUSGUARD-START"
    public static let lockMarkerEnd = "# FOCUSGUARD-END"
    public static let commandFile = "/tmp/focusguard.command"
    public static let daemonLabel = "com.focusguard.blocker"
    public static let defaultUnlockDelay: Int = 1200 // 20 minutes
    public static let defaultMaxUnlocksPerDay: Int = 2
    public static let defaultCooldownDuration: Int = 900 // 15 minutes
    public static let unlockHistoryFile = "\(configDir)/.unlock_history"

    public static let chromePrefsDir = "/Library/Managed Preferences"
    public static let chromePlistName = "com.google.Chrome"
}

/// The current state of the blocker
public enum BlockerStatus: String, Codable {
    case locked
    case unlockPending
    case unlocked
}

/// Status info written by daemon, read by app
public struct StatusInfo: Codable {
    public var status: BlockerStatus
    public var blockedDomains: [String]
    public var unlockRequestTime: Date?
    public var unlockDelay: Int
    public var lastEnforced: Date?
    // New: escalating delays, daily budget, cooldown
    public var unlocksToday: Int
    public var maxUnlocksPerDay: Int
    public var cooldownEndTime: Date?
    public var cooldownDuration: Int

    public init(
        status: BlockerStatus = .locked,
        blockedDomains: [String] = [],
        unlockRequestTime: Date? = nil,
        unlockDelay: Int = FocusGuardConfig.defaultUnlockDelay,
        lastEnforced: Date? = nil,
        unlocksToday: Int = 0,
        maxUnlocksPerDay: Int = FocusGuardConfig.defaultMaxUnlocksPerDay,
        cooldownEndTime: Date? = nil,
        cooldownDuration: Int = FocusGuardConfig.defaultCooldownDuration
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

    /// How many unlocks remain today
    public var unlocksRemaining: Int {
        max(0, maxUnlocksPerDay - unlocksToday)
    }

    /// Whether the daily budget is exhausted
    public var budgetExhausted: Bool {
        unlocksToday >= maxUnlocksPerDay
    }
}

/// Commands the app can send to the daemon via file-based IPC
public enum DaemonCommand: String, Codable {
    case lock
    case unlock
    case addDomain
    case removeDomain
    case refresh
}

public struct CommandMessage: Codable {
    public var command: DaemonCommand
    public var argument: String?

    public init(command: DaemonCommand, argument: String? = nil) {
        self.command = command
        self.argument = argument
    }
}
