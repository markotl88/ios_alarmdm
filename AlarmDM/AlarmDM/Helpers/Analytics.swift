//
//  Analytics.swift
//  AlarmDM
//
//  How much of the app is actually used, as a handful of counts and nothing
//  else.
//

import Foundation

#if canImport(Aptabase)
import Aptabase
#endif

/// Counts, and only counts.
///
/// What a person bookmarks lives in their own iCloud database, which is not
/// readable from here and should not be. So the one question worth asking —
/// does anyone use the bookmarks at all — can only be answered by the app
/// saying so, and it says so without saying anything about the person: no
/// identifier, no note, no episode, no position. An event name and, at most,
/// which button it came from.
///
/// Aptabase keeps no device identifier, cookie or fingerprint, and its
/// European servers keep no IP address, which is what makes this a count
/// rather than a record about someone.
enum Analytics {

    /// Pasted from the Aptabase dashboard once the app is registered there.
    /// Empty means nothing is sent, which is also what a fork of this project
    /// should do.
    private static let appKey = "A-EU-9320487015"

    /// Debug builds are the developer's own use, and would drown a few
    /// thousand real listeners in one afternoon of testing.
    private static var isEnabled: Bool {
        #if DEBUG
        return false
        #else
        return !appKey.isEmpty && !AppSettings.shared.suppressesUsageStatistics
        #endif
    }

    static func start() {
        #if canImport(Aptabase)
        guard isEnabled else { return }
        Aptabase.shared.initialize(appKey: appKey)
        #endif
    }

    static func record(_ event: Event, _ properties: [String: String] = [:]) {
        #if canImport(Aptabase)
        guard isEnabled else { return }
        Aptabase.shared.trackEvent(event.rawValue, with: properties)
        #endif
    }

    enum Event: String {
        /// A bookmark was made, and from where.
        case bookmarkCreated = "bookmark_created"
        /// The list of them was opened.
        case bookmarksOpened = "bookmarks_opened"
        /// One of them was tapped and led back into the audio. The one that
        /// matters: making bookmarks is easy, returning to them is the test.
        case bookmarkPlayed = "bookmark_played"
        /// How many a person has, as a range, once a week at most. Says how
        /// many people have any at all without ever describing one.
        case bookmarksHeld = "bookmarks_held"
    }

    // MARK: - The weekly count

    private static let countedKey = "bookmarksCountedAt"

    /// A range rather than a number, sent at most once a week: enough to tell
    /// nobody from a few from a hundred, not enough to follow anybody.
    static func recordBookmarksHeld(_ count: Int, defaults: UserDefaults = .standard) {
        guard isEnabled else { return }

        let last = defaults.object(forKey: countedKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 24 * 60 * 60 else { return }
        defaults.set(Date(), forKey: countedKey)

        record(.bookmarksHeld, ["range": range(of: count)])
    }

    static func range(of count: Int) -> String {
        switch count {
        case 0: return "0"
        case 1...5: return "1-5"
        case 6...20: return "6-20"
        default: return "20+"
        }
    }
}
