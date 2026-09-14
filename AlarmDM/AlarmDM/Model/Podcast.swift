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
        case .ostalo: return "Ostalo"
        }
    }

    var description: String {
        switch self {
        case .alarmSaDaskomIMladjom: return "Ponedeljak - četvrtak, od 08 do 10h."
        case .ljudiIzPodzemlja: return "Specijalizovana za punk/hardcore zvuk."
        case .unutrasnjaEmigracija: return "Svi mi emigranti. Svakog dana od 11h"
        case .vecernjaSkolaRokenrola: return "Rokenrol za večernje sate."
        case .naIviciOfsajda: return "Romantizovani fudbalski istorijat."
        case .nepopularnoMisljenje: return "Teme o kojima se ćuti."
        case .sportskiPozdrav: return "Sportska emisija."
        case .jbt: return "Jovana, Boris, Tatjana o društveno-političkim dešavanjima. Petkom u 18:05."
        case .priceUMagli: return "Radio-drama."
        case .rastrojavanje: return "Četvrtkom o važnim temama."
        case .topleLjuckePrice: return "Emisija sa toplim ljudskim pričama."
        case .punaUstaPoezije: return "Emisija posvećena poeziji."
        case .citanjac: return "Čitanje uz mikrofon."
        case .falis: return "Prenosi sa Festivala alternative i ljevice u Šibeniku, 2024."
        case .ostalo: return "Epizode van redovnih emisija."
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

    /// True once the listen has gone past the end of the show. Kept here
    /// rather than read off the stored flag alone so a position restored
    /// mid-session answers the same way.
    var hasReachedEnd: Bool {
        let end = endOfShow
        return end > 0 && playedPosition >= end
    }

    /// Where the show is over and the credits start rolling — the line an
    /// episode has to cross to count as listened to. Falls back to the full
    /// running time when nothing has been measured.
    var endOfShow: TimeInterval {
        let duration = durationInSeconds
        guard duration > 0 else { return 0 }
        return max(0, duration - outro)
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

extension Podcast {
    init(from podcastRealm: PodcastRealm) {
        self.id = UUID(uuidString: podcastRealm.id) ?? UUID() // Convert String to UUID, fallback to a new UUID if conversion fails
        self.title = podcastRealm.title
        self.subtitle = podcastRealm.subtitle
        self.createdDate = podcastRealm.createdAt
        self.timestamp = podcastRealm.timestamp
        self.podcastUrl = podcastRealm.podcastUrl
        self.duration = podcastRealm.duration
        self.lengthInBytes = podcastRealm.lengthInBytes
        self.itunesDuration = podcastRealm.itunesDuration
        self.show = Show(rawValue: podcastRealm.show ?? "") ?? .ostalo
        self.fileUrl = podcastRealm.fileUrl
        self.isFavorite = podcastRealm.isFavorite
        self.isWithMusic = podcastRealm.isWithMusic
    }
}
