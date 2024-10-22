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
    case vecernjaSkolaRokenrola
    case sportskiPozdrav
    case unutrasnjaEmigracija
    case naIviciOfsajda
    case topleLjuckePrice
    case rastrojavanje
    case punaUstaPoezije
    case mozemoSamoDaSeSlikamo
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .alarmSaDaskomIMladjom: return "Alarm sa Daškom i Mlađom"
        case .ljudiIzPodzemlja: return "Ljudi iz podzemlja"
        case .naIviciOfsajda: return "Na ivici ofsajda"
        case .rastrojavanje: return "Rastrojavanje"
        case .vecernjaSkolaRokenrola: return "Večernja škola rokenrola"
        case .sportskiPozdrav: return "Sportski pozdrav"
        case .topleLjuckePrice: return "Tople Ljucke Priče"
        case .mozemoSamoDaSeSlikamo: return "Možemo samo da se slikamo"
        case .punaUstaPoezije: return "Puna usta poezije"
        case .unutrasnjaEmigracija: return "Unutrašnja emigracija"
        }
    }
    
    var description: String {
        switch self {
        case .alarmSaDaskomIMladjom: return "Svakog radnog dana od 07 do 10h."
        case .ljudiIzPodzemlja: return "Specijalizovana za punk/hardcore zvuk. Sreda u 20h."
        case .naIviciOfsajda: return "Romantizovani fudbalski istorijat. Nedelja u 20h."
        case .rastrojavanje: return "Četvrtkom o važnim temama."
        case .vecernjaSkolaRokenrola: return "Rokenrol za večernje sate."
        case .sportskiPozdrav: return "Sportska emisija. Svake nedelje u 20h."
        case .topleLjuckePrice: return "Emisija sa toplim ljudskim pričama."
        case .mozemoSamoDaSeSlikamo: return "Satira i humor."
        case .punaUstaPoezije: return "Emisija posvećena poeziji."
        case .unutrasnjaEmigracija: return "Svi mi emigranti."
        }
    }
    
    var imageName: String {
        switch self {
        case .alarmSaDaskomIMladjom: return "img_alarm"
        case .ljudiIzPodzemlja: return "img_ljp"
        case .naIviciOfsajda: return "img_nio"
        case .rastrojavanje: return "img_rastrojavanje"
        case .vecernjaSkolaRokenrola: return "img_vecernja_skola_rokenrola"
        case .sportskiPozdrav: return "img_sportski_pozdrav"
        case .topleLjuckePrice: return "img_tljp"
        case .mozemoSamoDaSeSlikamo: return "img_msdss"
        case .punaUstaPoezije: return "img_pup"
        case .unutrasnjaEmigracija: return "img_unutrasnja_emigracija"
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
    
    var show: Show?
    var fileUrl: String?
    var isFavorite = false
    var isWithMusic = false
    var isDownloaded: Bool {
        fileUrl != nil
    }
    var bookmarks: [Bookmark]?
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
        self.show = Show(rawValue: podcastRealm.show ?? "")
        self.fileUrl = podcastRealm.fileUrl
        self.isFavorite = podcastRealm.isFavorite
        self.isWithMusic = podcastRealm.isWithMusic
    }
}
