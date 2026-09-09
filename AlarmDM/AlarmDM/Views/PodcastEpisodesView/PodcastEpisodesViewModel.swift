//
//  PodcastEpisodesViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI
import RealmSwift

/// The episode list filters. Only ever shown inside a single show — the Radio
/// tab is a short "what is new" list where filtering would be noise.
enum EpisodeFilter: String, CaseIterable, Identifiable {
    case withMusic
    case withoutMusic
    case downloaded
    case favourites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .withMusic: return "Sa muzikom"
        case .withoutMusic: return "Bez muzike"
        case .downloaded: return "Preuzeto"
        case .favourites: return "Omiljeno"
        }
    }

    var systemImage: String {
        switch self {
        case .withMusic: return "music.note"
        case .withoutMusic: return "music.note.slash"
        case .downloaded: return "arrow.down.circle"
        case .favourites: return "heart"
        }
    }
}

final class PodcastEpisodesViewModel: ObservableObject {
    
    @Published var podcasts: [Podcast] = []
    /// nil means no filter. Tapping the active chip clears it.
    @Published var activeFilter: EpisodeFilter?
    @Published var errorMessage: String?
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreData: Bool = true
    
    private let podcastService: PodcastServiceProtocol
    private let selectedShow: Show

    var showTitle: String { selectedShow.displayName }

    /// Episodes after the active filter. Pagination still works off `podcasts`,
    /// so filtering never stops the list from loading more.
    var visiblePodcasts: [Podcast] {
        guard let activeFilter else { return podcasts }
        switch activeFilter {
        case .withMusic: return podcasts.filter { $0.isWithMusic }
        case .withoutMusic: return podcasts.filter { !$0.isWithMusic }
        case .downloaded: return podcasts.filter { $0.isDownloaded }
        case .favourites: return podcasts.filter { $0.isFavorite }
        }
    }

    /// Some shows publish both cuts of an episode, most do not. The music
    /// filters and the row badge only make sense where both exist.
    var hasBothMusicVariants: Bool {
        var seenWithMusic = false
        var seenWithoutMusic = false
        for podcast in podcasts {
            if podcast.isWithMusic { seenWithMusic = true } else { seenWithoutMusic = true }
            if seenWithMusic && seenWithoutMusic { return true }
        }
        return false
    }

    var availableFilters: [EpisodeFilter] {
        hasBothMusicVariants
            ? EpisodeFilter.allCases
            : [.downloaded, .favourites]
    }

    func toggle(_ filter: EpisodeFilter) {
        activeFilter = (activeFilter == filter) ? nil : filter
    }

    func toggleFavourite(_ podcast: Podcast) {
        EpisodeLibrary.shared.toggleFavourite(podcast)
        podcasts = loadPodcastsFromRealm()
    }

    func deleteDownload(_ podcast: Podcast) {
        EpisodeLibrary.shared.deleteDownload(podcast)
        podcasts = loadPodcastsFromRealm()
    }
    private var currentPage = 1
    private var totalPages: Int = 1
    private let repository = PodcastRepository.shared
    private var queryDate: String?
    
    init(podcastService: PodcastServiceProtocol = PodcastService(), show: Show) {
        self.podcastService = podcastService
        self.selectedShow = show
    }
    
    // MARK: - Fetch Podcasts from Server and Save to Realm
    func fetchData() {
        podcasts = loadPodcastsFromRealm()
        
        if let lastDate = podcasts.first?.createdDate?.iso8601String {
            getPodcasts(for: selectedShow.rawValue, from: lastDate, isBefore: false)
        } else {
            getPodcasts(for: selectedShow.rawValue, from: nil, isBefore: true)
        }
    }
    
    // MARK: - Fetch Podcasts from Realm
    private func loadPodcastsFromRealm() -> [Podcast] {
        repository.podcasts(for: selectedShow)
    }
    
    
    private func getPodcasts(for show: String?, from date: String?, isBefore: Bool?) {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        podcastService.getPodcasts(for: show, page: currentPage, date: date, isBefore: isBefore) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMore = false
            switch result {
            case .success(let paginationData):
                
                self.repository.save(paginationData.podcasts.map { Podcast(from: $0) })
                self.podcasts = loadPodcastsFromRealm()
                
                if (isBefore ?? true) {
                    if paginationData.podcasts.isEmpty || self.currentPage > (paginationData.totalPages ?? 1) {
                        self.hasMoreData = false
                    } else {
                        self.currentPage += 1
                        self.totalPages = (paginationData.totalPages ?? 1)
                    }
                }
                
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Fetch More Data if Needed
    func fetchDataIfNeeded(currentItem: Podcast?) {
        guard currentItem != nil else { return }
        guard !isLoadingMore else { return }
        guard hasMoreData else { return }
        
        if currentPage < totalPages {
            getPodcasts(for: selectedShow.rawValue, from: queryDate, isBefore: true)
        } else if currentPage == totalPages, let date = currentItem?.createdDate?.iso8601String {
            currentPage = 1
            queryDate = date
            getPodcasts(for: selectedShow.rawValue, from: queryDate, isBefore: true)
        }
    }
}
