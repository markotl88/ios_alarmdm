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
    var timestamp: String?
    var podcastUrl = ""
    var duration = ""
    var lengthInBytes = 0.0
    var itunesDuration = ""
    
    var show: Show
    var fileUrl: String?
    var isFavorite = false
    var isWithMusic = false
    var isDownloaded: Bool {
        fileUrl != nil
    }
}

extension Podcast {
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
        self.timestamp = response.timestamp
        self.podcastUrl = response.podcastUrl
        self.duration = response.duration
        self.lengthInBytes = response.lengthInBytes
        self.itunesDuration = response.itunesDuration
        self.show = Show(rawValue: response.showType ?? "") ?? .ostalo
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
