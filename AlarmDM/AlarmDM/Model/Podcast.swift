//
//  Podcast.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation

enum Show: String, CaseIterable, Identifiable {
    case alarmSaDaskomIMladjom
    case ljudiIzPodzemlja
    case unutrasnjaEmigracija
    case vecernjaSkolaRokenrola
    case naIviciOfsajda
    case nepopularnoMisljenje
    case sportskiPozdrav
    case jbt
    case priceUMagli
    case rastrojavanje
    case topleLjuckePrice
    case punaUstaPoezije
    case citanjac
    case falis
    /// Bucket for episodes the backend could not classify. Never listed in the
    /// Shows tab — it exists so an unknown title stops masquerading as Alarm.
    case ostalo

    var id: String { self.rawValue }

    /// The order the Shows tab lists them in, set by hand rather than by
    /// episode count or recency — it is an editorial decision, not a metric.
    static let featured: [Show] = [
        .alarmSaDaskomIMladjom,
        .unutrasnjaEmigracija,
        .ljudiIzPodzemlja,
        .vecernjaSkolaRokenrola,
        .sportskiPozdrav,
        .naIviciOfsajda,
        .nepopularnoMisljenje,
        .jbt,
    ]

    /// Shows that have stopped publishing, or one-offs. Listed under Arhiva.
    static var archived: [Show] {
        allCases.filter { $0 != .ostalo && !featured.contains($0) }
    }

    static var listed: [Show] { featured + archived }

    var displayName: String {
        switch self {
        case .alarmSaDaskomIMladjom: return "Alarm sa Daškom i Mlađom"
        case .ljudiIzPodzemlja: return "Ljudi iz podzemlja"
        case .unutrasnjaEmigracija: return "Unutrašnja emigracija"
        case .vecernjaSkolaRokenrola: return "Večernja škola rokenrola"
        case .naIviciOfsajda: return "Na ivici ofsajda"
        case .nepopularnoMisljenje: return "Nepopularno mišljenje"
        case .sportskiPozdrav: return "Sportski pozdrav"
        case .jbt: return "JBT"
        case .priceUMagli: return "Priče u magli"
        case .rastrojavanje: return "Rastrojavanje"
        case .topleLjuckePrice: return "Tople Ljucke Priče"
        case .punaUstaPoezije: return "Puna usta poezije"
        case .citanjac: return "Čitanjac"
        case .falis: return "FALIŠ"
        // Its own key: "Ostalo" is also the last tab, which is "More" in
        // English, where this one is "Other".
        case .ostalo: return String(localized: "show.other", defaultValue: "Ostalo")
        }
    }

    var description: String {
        switch self {
        case .alarmSaDaskomIMladjom: return String(localized: "Od ponedeljka do četvrtka, od 8 do 10 h.")
        case .ljudiIzPodzemlja: return String(localized: "DIY punk radio emisija iz Novog Sada.")
        case .unutrasnjaEmigracija: return String(localized: "180 minuta muzike i subverzivnog delovanja.")
        case .vecernjaSkolaRokenrola: return String(localized: "Rokenrol za večernje sate.")
        case .naIviciOfsajda: return String(localized: "Radijska emisija koja romansira istorijat fudbala.")
        case .nepopularnoMisljenje: return String(localized: "Gosti podkasta govore o društveno-političkim temama, aktivizmu i kulturi.")
        case .sportskiPozdrav: return String(localized: "Od Subotice do Surdulice, pregled aktuelnosti domaćeg sporta.")
        case .jbt: return String(localized: "Jovana, Boris i Tatjana o društveno-političkim dešavanjima. Petkom u 18:05.")
        case .priceUMagli: return String(localized: "Radio-drama.")
        case .rastrojavanje: return String(localized: "Četvrtkom o važnim temama.")
        case .topleLjuckePrice: return String(localized: "Daško sa gostima.")
        case .punaUstaPoezije: return String(localized: "Emisija posvećena poeziji.")
        case .citanjac: return String(localized: "Bulevar Books za decu.")
        case .falis: return String(localized: "Prenosi sa Festivala alternative i ljevice u Šibeniku, 2024.")
        case .ostalo: return String(localized: "Epizode van redovnih emisija.")
        }
    }

    /// Some shows raise money on a Patreon of their own, separate from the
    /// station's. Nil for the rest.
    var patreonURL: URL? {
        switch self {
        case .unutrasnjaEmigracija: return URL(string: "https://www.patreon.com/unutrasnjaemigracija")
        case .ljudiIzPodzemlja: return URL(string: "https://www.patreon.com/ljudiizpodzemlja")
        case .vecernjaSkolaRokenrola: return URL(string: "https://www.patreon.com/vecernjaskola")
        case .sportskiPozdrav: return URL(string: "https://www.patreon.com/sportskipozdrav")
        case .naIviciOfsajda: return URL(string: "https://www.patreon.com/naiviciofsajda")
        default: return nil
        }
    }

    /// In the Shows tab's order, so the Podrži screen reads the same way.
    static var withOwnPatreon: [Show] {
        listed.filter { $0.patreonURL != nil }
    }

    /// How long this show's closing credits run. The backend sends the same
    /// number per episode and that one wins; this is what an episode
    /// downloaded before the field existed, or fetched with the function
    /// unreachable, falls back on.
    ///
    /// Zero means unmeasured rather than absent, and an episode then ends at
    /// its last second — which is how it behaved before any of this.
    var outroSeconds: TimeInterval {
        switch self {
        case .alarmSaDaskomIMladjom, .unutrasnjaEmigracija: return 20
        case .ljudiIzPodzemlja: return 5
        default: return 0
        }
    }

    /// Shows added after the original artwork set fall back to the radio image
    /// rather than rendering an empty frame.
    var imageName: String {
        switch self {
        case .alarmSaDaskomIMladjom: return "img_alarm"
        case .ljudiIzPodzemlja: return "img_ljp"
        case .unutrasnjaEmigracija: return "img_unutrasnja_emigracija"
        case .vecernjaSkolaRokenrola: return "img_vecernja_skola_rokenrola"
        case .naIviciOfsajda: return "img_nio"
        case .sportskiPozdrav: return "img_sportski_pozdrav"
        case .rastrojavanje: return "img_rastrojavanje"
        case .topleLjuckePrice: return "img_tljp"
        case .punaUstaPoezije: return "img_pup"
        case .jbt: return "img_jbt"
        case .nepopularnoMisljenje: return "img_nepopularno"
        case .falis: return "img_falis"
        case .priceUMagli, .citanjac, .ostalo:
            return "img_radio"
        }
    }
}

struct Podcast: Identifiable, Equatable {
    var id: UUID = UUID()
    var title = ""
    var subtitle = ""
    var createdDate: Date?
    /// When it went out live. Only the full cut has one.
    var airedAt: Date?
    var timestamp: String?
    var podcastUrl = ""
    var duration = ""
    var lengthInBytes = 0.0
    var itunesDuration = ""
    
    var show: Show
    /// From the backend. Nil until an episode is fetched by a version that
    /// asks for it, and the show's own figure stands in meanwhile.
    var outroSeconds: TimeInterval?
    var fileUrl: String?
    /// How far the last listen got, and when. Written by the player, never by
    /// the feed.
    var playedPosition: TimeInterval = 0
    var playedAt: Date?
    var isPlayed = false
    var isFavorite = false
    var isWithMusic = false
    var isDownloaded: Bool {
        fileUrl != nil
    }
}

extension Podcast {
    /// The closing credits, in seconds: what the backend measured for this
    /// episode, or the show's figure when it has not measured one. Backend
    /// zero is unmeasured, not measured-as-none, so it does not overrule a
    /// show the app knows about.
    var outro: TimeInterval {
        if let outroSeconds, outroSeconds > 0 { return outroSeconds }
        return show.outroSeconds
    }

    /// Below this, a saved position is not worth returning to — the first
    /// seconds of an episode are quicker to hear again than to think about.
    static let resumeFloor: TimeInterval = 20

    /// Where pressing play should pick this episode up, or nil to start at
    /// the beginning. A finished episode starts over: its position is a record
    /// of the last listen, not an invitation to sit through the credits again.
    var resumePosition: TimeInterval? {
        guard !isPlayed, playedPosition > Podcast.resumeFloor else { return nil }
        let end = endOfShow
        guard end <= 0 || playedPosition < end else { return nil }
        // A few seconds back, for the same reason a bookmark takes a few: you
        // stopped listening slightly before you stopped playing.
        return max(0, playedPosition - 3)
    }

    /// How far through the show a listen got, as a fraction — for the line
    /// under an episode in a list.
    ///
    /// Nil for an episode that has not been started and for one that is
    /// finished: an empty line and a full line each say nothing, and drawing
    /// them puts a rule under every row in the list for no reason.
    var listeningProgress: Double? {
        guard !isPlayed, playedPosition > 0 else { return nil }
        let end = endOfShow
        guard end > 0 else { return nil }
        // A minimum, so a minute into a three-hour episode is still visible as
        // something rather than as a line that was never drawn.
        return min(max(playedPosition / end, 0.02), 1)
    }

    /// How much show is still in front of you, in words — the text beside the
    /// bar in a list. Measured to the end of the show rather than to the end
    /// of the file, so it does not promise twenty seconds of credits.
    ///
    /// Nil in exactly the cases where the bar is nil, so the two appear and
    /// disappear together.
    var remainingDescription: String? {
        guard listeningProgress != nil else { return nil }
        let left = max(0, endOfShow - playedPosition)
        guard left >= 60 else { return String(localized: "Još manje od minuta") }

        let hours = Int(left) / 3600
        let minutes = (Int(left) % 3600) / 60
        if hours > 0 {
            return minutes > 0
                ? String(localized: "Još \(hours) h \(minutes) min")
                : String(localized: "Još \(hours) h")
        }
        return String(localized: "Još \(minutes) min")
    }

    /// True once the listen has gone past the end of the show. Kept here
    /// rather than read off the stored flag alone so a position restored
    /// mid-session answers the same way.
    var hasReachedEnd: Bool {
        let end = endOfShow
        return end > 0 && playedPosition >= end
    }

    /// How much of an episode has to be behind you before it counts as heard.
    /// One of the two conditions; see endOfShow for the other.
    static let playedFraction = 0.95

    /// The finish line: both conditions, so whichever of the two lies later.
    /// Ninety-five percent of the running time has to be behind you *and* the
    /// closing credits have to have started.
    ///
    /// Which one binds depends on the length. On a three-hour Alarm the
    /// credits are the later line by eight minutes, so they are what settles
    /// it; on a five-minute episode ninety-five percent falls after the
    /// credits begin, and it is the percentage that settles it. Requiring
    /// both means an episode is never called heard with a stretch of show
    /// still in front of it.
    ///
    /// Falls back to the running time alone when the episode does not say how
    /// long it runs.
    var endOfShow: TimeInterval {
        let duration = durationInSeconds
        guard duration > 0 else { return 0 }
        return max(0, max(duration * Podcast.playedFraction, duration - outro))
    }

    var durationInSeconds: Double {
        // ako imaš string tipa "24:35"
        let components = itunesDuration.split(separator: ":").compactMap { Double($0) }
        switch components.count {
        case 3: return components[0] * 3600 + components[1] * 60 + components[2]
        case 2: return components[0] * 60 + components[1]
        case 1: return components[0]
        default: return 0
        }
    }
}

extension Podcast {
    init(from response: PodcastResponse) {
        // Identity comes from the media URL, never from a fresh UUID — see UUID.stable.
        let identitySource = response.id.isEmpty ? response.podcastUrl : response.id
        self.id = .stable(from: identitySource)
        self.title = response.title
        self.subtitle = response.subtitle
        self.createdDate = response.createdDate.formattedCreatedDate
        self.airedAt = response.airedAt?.formattedCreatedDate
        self.timestamp = response.timestamp
        self.podcastUrl = response.podcastUrl
        self.duration = response.duration
        self.lengthInBytes = response.lengthInBytes
        self.itunesDuration = response.itunesDuration
        self.show = Show(rawValue: response.showType ?? "") ?? .ostalo
        self.outroSeconds = response.outroSeconds
        self.isWithMusic = response.withMusic
    }
}

// An episode used to be built from a Realm row here. Both that conversion and
// the database behind it are gone: the id it produced came from
// `UUID(uuidString:) ?? UUID()` over an identifier the old app generated at
// random, so it was never the id the feed gives the same episode, and
// everything written under it was invisible from the moment it was written.

// MARK: - Which cut

extension Podcast {
    /// Only the cut without music is marked. With music is how the show goes
    /// out, so it is the default everywhere and needs no sign; the cut that
    /// differs from it is the one that has to say so. Two different marks
    /// never looked like a pair anyway — one was a glyph from the font, the
    /// other a symbol.
    static let withoutMusicSymbol = "music.note.slash"
}

extension Sequence where Element == Podcast {
    /// The shows that appear here in both cuts. Only their rows need to say
    /// which cut they are: every other show publishes one, and a mark on it
    /// answers a question nobody asked.
    var showsInBothCuts: Set<Show> {
        var withMusic: Set<Show> = []
        var withoutMusic: Set<Show> = []
        for podcast in self {
            if podcast.isWithMusic { withMusic.insert(podcast.show) } else { withoutMusic.insert(podcast.show) }
        }
        return withMusic.intersection(withoutMusic)
    }
}
