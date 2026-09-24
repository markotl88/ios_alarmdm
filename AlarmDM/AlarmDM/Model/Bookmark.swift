//
//  Bookmark.swift
//  AlarmDM
//
//  A moment worth coming back to. Made with one tap, sorted out later.
//

import Foundation

enum BookmarkCategory: String, CaseIterable, Identifiable {
    // Declaration order is the order the picker offers them in - allCases
    // follows it.
    case muzika
    case film
    case serija
    case knjiga
    case urnebesno
    case rejdz
    case mladja
    case dasko
    case strip
    case zoli

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muzika: return String(localized: "Muzika")
        case .film:   return String(localized: "Film")
        case .serija: return String(localized: "Serija")
        case .knjiga: return String(localized: "Knjiga")
        case .strip:  return String(localized: "Strip")
        case .urnebesno: return String(localized: "Urnebesno")
        case .rejdz:  return String(localized: "Rejdž")
        case .dasko:  return String(localized: "Masti")
        case .mladja: return String(localized: "Dobar čovek")
        case .zoli:   return String(localized: "Zoli")
        }
    }

    var assetName: String? {
        switch self {
        // Both of them, the way the app icon has them.
        case .urnebesno: return "bookmark-dasko-mladja"
        case .rejdz, .dasko: return "bookmark-dasko"
        case .mladja: return "bookmark-mladja"
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .muzika: return "music.note"
        case .film:   return "film"
        case .serija: return "tv"
        case .knjiga: return "book"
        case .strip:  return "books.vertical"
        case .urnebesno: return "face.smiling"
        case .rejdz, .dasko, .mladja: return "person.crop.circle"
        case .zoli:   return "guitars"
        }
    }
}

struct Bookmark: Identifiable, Equatable {

    var id: UUID
    var createdAt: Date

    /// Seconds into the episode. Zero for something caught on live radio,
    /// which has no position to point at.
    var position: Double

    /// Nil until someone says what it was. The whole point of the button is
    /// that it does not ask at the moment you press it.
    var category: BookmarkCategory?
    var note: String

    /// A copy of what was playing, not a lookup. The episode row can be
    /// evicted from the cache, and a bookmark that cannot say what it belongs
    /// to is worthless.
    var episodeTitle: String
    var show: Show?

    /// Nil until a live capture finds the episode it fell inside.
    var podcastId: UUID?

    /// Caught on live radio rather than inside an episode. Stays true after
    /// the episode turns up, because `createdAt` plus this is what lets the
    /// position be worked out again if the broadcast time is ever corrected.
    var capturedLive: Bool

    /// Caught live and still without an episode: nothing to open, nowhere to
    /// jump. Not the same as having been caught live, which never changes.
    var isAwaitingEpisode: Bool { capturedLive && podcastId == nil }

    /// What you wrote beats what the feed called the episode. Four bookmarks
    /// inside the same episode are four identical rows otherwise.
    var displayTitle: String {
        note.isEmpty ? episodeTitle : note
    }

    /// The episode steps down to the second line once the note has taken the
    /// first, so a row never stops saying where it came from.
    var displaySubtitle: String? {
        note.isEmpty ? show?.displayName : episodeTitle
    }

    /// mm:ss into the episode, or the moment it was caught for live radio.
    var positionText: String {
        guard !isAwaitingEpisode else {
            return Bookmark.liveFormatter.string(from: createdAt)
        }
        let total = Int(position)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private static let liveFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sr_RS")
        formatter.dateFormat = "d.M. 'u' HH:mm"
        return formatter
    }()
}
