//
//  Bookmark.swift
//  AlarmDM
//
//  A moment worth coming back to. Made with one tap, sorted out later.
//

import Foundation

enum BookmarkCategory: String, CaseIterable, Identifiable {
    case muzika
    case film
    case knjiga
    case strip
    case fora

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muzika: return "Muzika"
        case .film:   return "Film"
        case .knjiga: return "Knjiga"
        case .strip:  return "Strip"
        case .fora:   return "Fora"
        }
    }

    var systemImage: String {
        switch self {
        case .muzika: return "music.note"
        case .film:   return "film"
        case .knjiga: return "book"
        case .strip:  return "books.vertical"
        case .fora:   return "face.smiling"
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

    /// Nil when this was caught during live radio.
    var podcastId: UUID?

    var isLive: Bool { podcastId == nil }

    /// mm:ss into the episode, or the moment it was caught for live radio.
    var positionText: String {
        guard !isLive else {
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
