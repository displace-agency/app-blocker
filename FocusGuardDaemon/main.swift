import Foundation

// FocusGuard daemon entry point. All logic lives in Daemon and its
// collaborators (Logger, Stats, AppBlocker, SocketServer, HostsWriter).
// Timers run on a serial DispatchQueue, so we just keep the process alive.

let daemon = Daemon()
daemon.start()
dispatchMain()
