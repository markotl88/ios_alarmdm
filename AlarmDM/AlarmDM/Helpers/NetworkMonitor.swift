//
//  NetworkMonitor.swift
//  AlarmDM
//
//  Answers one question for the WiFi-only download rule: is the current
//  connection metered?
//

import Foundation
import Network

final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.alarmdm.network-monitor")
    private let lock = NSLock()
    private var metered: Bool

    /// True on cellular and on a personal hotspot (`isExpensive`), and when the
    /// system is in Low Data Mode (`isConstrained`) — both mean "do not pull
    /// down a hundred megabytes without asking".
    var isMetered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return metered
    }

    private init() {
        // Seeded synchronously, so a download started in the first moments
        // after launch is judged on the real connection and not on a default.
        let path = monitor.currentPath
        metered = path.isExpensive || path.isConstrained

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.metered = path.isExpensive || path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
