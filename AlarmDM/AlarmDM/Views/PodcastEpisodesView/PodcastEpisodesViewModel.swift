//
//  PodcastEpisodesViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI
import Combine

/// The episode list filters. Only ever shown inside a single show - the Radio
/// tab is a short "what is new" list where filtering would be noise.
enum EpisodeFilter: String, CaseIterable, Identifiable {
    case withMusic
    case withoutMusic
    case downloaded
    case favourites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .withMusic: return String(localized: "Sa muzikom")
        case .withoutMusic: return String(localized: "Bez muzike")
        case .downloaded: return String(localized: "Preuzeto")
        // Its own key: as a filter this is a plural in English, where the
        // same word on a row is an adjective.
        case .favourites: return String(localized: "filter.favourites", defaultValue: "Omiljeno")
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

/// Keep newly finished rows in place until the next refresh/open, while
/// hiding episodes that were already finished when this list was loaded.
struct EpisodeVisibility {
    private var unfinishedThisSession = Set<UUID>()

    mutating func remember(_ episodes: [Podcast]) {
        unfinishedThisSession.formUnion(episodes.filter { !$0.isPlayed && !$0.hasReachedEnd }.map(\.id))
    }

    func visible(_ episodes: [Podcast], filter: EpisodeFilter?, showsPlayed: Bool) -> [Podcast] {
        episodes.filter { episode in
            switch filter {
            case .downloaded: return episode.isDownloaded
            case .favourites: return episode.isFavorite
            case .withMusic where !episode.isWithMusic: return false
            case .withoutMusic where episode.isWithMusic: return false
            default: break
            }
            return showsPlayed || (!episode.isPlayed && !episode.hasReachedEnd)
                || unfinishedThisSession.contains(episode.id)
        }
    }
}

final class PodcastEpisodesViewModel: ObservableObject {
    
    @Published var podcasts: [Podcast] = [] {
        didSet { visibility.remember(podcasts) }
    }
    private var visibility = EpisodeVisibility()
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
        visibility.visible(podcasts, filter: activeFilter, showsPlayed: AppSettings.shared.showsPlayedEpisodes)
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
    }

    func deleteDownload(_ podcast: Podcast) {
        EpisodeLibrary.shared.deleteDownload(podcast)
    }

    func download(_ podcast: Podcast) {
        EpisodeLibrary.shared.download(podcast)
    }

    func isDownloading(_ podcast: Podcast) -> Bool {
        EpisodeLibrary.shared.isDownloading(podcast)
    }
    private var currentPage = 1
    private var totalPages: Int = 1
    private let repository = PodcastRepository.shared
    private var queryDate: String?
    private var cancellables = Set<AnyCancellable>()
    
    init(podcastService: PodcastServiceProtocol = PodcastService(), show: Show) {
        self.podcastService = podcastService
        self.selectedShow = show

        // The list holds a snapshot taken from the store when it loaded, so a
        // favourite or a deleted download has to be reflected here explicitly.
        // The Radio tab already listened; this screen did not, so the heart
        // only appeared when something else happened to reload the list.
        EpisodeLibrary.shared.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.podcasts = self.storedPodcasts()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Fetch episodes from the server and save them
    func fetchData() {
        visibility = EpisodeVisibility()
        repository.refreshFromStore()
        podcasts = storedPodcasts()
        
        if let lastDate = podcasts.first?.createdDate?.iso8601String {
            getPodcasts(for: selectedShow.rawValue, from: lastDate, isBefore: false)
        } else {
            getPodcasts(for: selectedShow.rawValue, from: nil, isBefore: true)
        }
    }
    
    // MARK: - Read episodes back
    private func storedPodcasts() -> [Podcast] {
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
                self.podcasts = storedPodcasts()
                
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
