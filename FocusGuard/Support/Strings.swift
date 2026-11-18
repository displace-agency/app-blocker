import Foundation

/// Centralized user-facing strings. Plain constants keep a future move to
/// String(localized:) mechanical without pulling in .strings bundle infra now.
enum L10n {
    static let appName = "FocusGuard"

    enum Tab {
        static let sites = "Sites"
        static let apps = "Apps"
        static let schedule = "Schedule"
        static let stats = "Stats"
    }

    enum Action {
        static let startSession = "Start focus session"
        static let requestUnlock = "Request unlock"
        static let cancelUnlock = "Cancel unlock"
        static let lockNow = "Lock now"
        static let budgetExhausted = "No unlocks left today"
        static let quit = "Quit FocusGuard"
        static let replayIntro = "Replay introduction"
    }

    enum Sites {
        static let addPlaceholder = "Add a site to block…"
        static let myList = "My list"
        static let yourList = "Your list"
        static let groups = "Groups"
        static let empty = "No sites blocked yet."
        static let removeHint = "Removing sites is only possible during an unlock window."
    }

    enum Apps {
        static let choose = "Choose app…"
        static let empty = "No apps blocked yet."
        static let warning = "Blocked apps are force-quit while FocusGuard is locked. Unsaved work will be lost."
        static let onlyApplications = "Only apps inside /Applications can be blocked."
    }

    enum Schedule {
        static let empty = "No schedules. Add one to auto-lock on a weekly routine."
        static let add = "Add schedule"
        static let outsideHours = "Outside scheduled hours — sites are open."
        static let note = "When schedules exist, blocking is active only during their windows. Focus sessions and the blocklist still apply."
    }

    enum Unlock {
        static let title = "Request an unlock"
        static let keepLocked = "Keep it locked"
        static let confirm = "Confirm unlock"
    }

    enum Session {
        static let title = "Focus session"
        static let subtitle = "Locks instantly. Cannot be cancelled until it ends."
        static let active = "Focus session in progress"
    }

    enum Offline {
        static let banner = "FocusGuard daemon isn't responding"
        static let help = "The background blocker may have stopped. To restart it, run this in Terminal:"
        static let command = "sudo launchctl kickstart -k system/com.focusguard.blocker"
        static let outdated = "The background blocker is out of date. Run the updater to finish."
    }
}
