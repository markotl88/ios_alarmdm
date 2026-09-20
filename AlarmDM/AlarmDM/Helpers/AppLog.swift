//
//  AppLog.swift
//  AlarmDM
//
//  Where the app says what it is doing, so that what happened in a car an
//  hour ago can still be read afterwards.
//

import Foundation
import OSLog

/// Two destinations for one line.
///
/// `debugPrint` goes to Xcode's console and nowhere else, which is fine while
/// a cable is attached and useless everywhere the interesting things happen —
/// in a car, on a walk, on the morning the sync failed again. So every line
/// also goes to the system log, where `log show` can find it days later, and
/// to a file the phone itself can share when there is no Mac in reach.
enum AppLog {

    enum Category: String {
        case player
        case store
        case sync
        case carplay
        case library
        case network
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.msorg.daskoimladja"

    private static let loggers: [Category: Logger] = {
        var made: [Category: Logger] = [:]
        for category in [Category.player, .store, .sync, .carplay, .library, .network] {
            made[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        return made
    }()

    /// The file the phone can hand over. Kept in Documents rather than Caches
    /// because the system is free to delete Caches exactly when it is most
    /// needed — after a long session with the screen off.
    static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("alarmdm.log")
    }

    /// The session before the current one, kept by the rotation below. Often
    /// the half of the story that matters: the thing went wrong, the app was
    /// restarted, and only then did anyone think to export anything.
    static var previousFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("alarmdm-previous.log")
    }

    /// What there is to hand over, newest first, skipping what was never
    /// written.
    static var exportURLs: [URL] {
        [fileURL, previousFileURL].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Serial, so lines from the player, the store and CloudKit do not
    /// interleave halfway through a sentence.
    private static let queue = DispatchQueue(label: "AppLog", qos: .utility)

    /// Half a megabyte is a few hours of everything, and one rotation keeps
    /// the session before this one — which is often the one that matters.
    private static let sizeLimit = 512 * 1024

    static func write(_ category: Category, _ message: String) {
        // Public on purpose: these lines carry positions, episode ids and
        // store counts, none of it private and all of it worthless redacted.
        loggers[category]?.log("\(message, privacy: .public)")

        queue.async {
            appendToFile("\(timestamp()) [\(category.rawValue)] \(message)\n")
        }
    }

    // MARK: - The file

    private static func appendToFile(_ line: String) {
        let url = fileURL
        let data = Data(line.utf8)

        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)

        rotateIfNeeded(handle: handle, url: url)
    }

    private static func rotateIfNeeded(handle: FileHandle, url: URL) {
        guard let size = try? handle.offset(), size > sizeLimit else { return }

        let previous = previousFileURL
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
