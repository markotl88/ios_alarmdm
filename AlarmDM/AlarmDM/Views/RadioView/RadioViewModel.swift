//
//  RadioViewModel.swift
//  AlarmDM
//

import Foundation
import Combine

final class RadioViewModel: ObservableObject {

    @Published var livestreamUrl: URL?
    @Published var latestPodcasts: [Podcast] = [] {
        didSet { visibility.remember(latestPodcasts) }
    }
    private var visibility = EpisodeVisibility()
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var activeFilter: EpisodeFilter?

    /// How many episodes are on screen. Grows as the list is scrolled; the API
    /// is only asked for more when the store runs out.
    private var displayLimit = 20
    private var nextPage = 1
    private var reachedEnd = false

    private let podcastService: PodcastServiceProtocol
    private let repository = PodcastRepository.shared
    private var cancellables = Set<AnyCancellable>()

    init(podcastService: PodcastServiceProtocol = PodcastService()) {
        self.podcastService = podcastService
        fetchLivestreamUrl()
        loadCached()

        EpisodeLibrary.shared.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.latestPodcasts = self.repository.latestPodcasts(limit: self.displayLimit)
            }
            .store(in: &cancellables)
    }

    /// Whatever is already on disk shows instantly; the network refresh follows.
    private func loadCached() {
        latestPodcasts = repository.latestPodcasts(limit: displayLimit)
    }

    var visiblePodcasts: [Podcast] {
        visibility.visible(latestPodcasts, filter: activeFilter, showsPlayed: AppSettings.shared.showsPlayedEpisodes)
    }

    var canLoadMore: Bool { !reachedEnd }

    /// Which shows publish both cuts, worked out from the loaded episodes. On a
    /// mixed list the badge has to be decided per show: Alarm ships both, most
    /// shows ship one, and a note on every row would say nothing.
    private var showsWithBothVariants: Set<Show> {
        latestPodcasts.showsInBothCuts
    }

    func showsMusicVariant(for podcast: Podcast) -> Bool {
        showsWithBothVariants.contains(podcast.show)
    }

    /// Across shows, "with music" says little - each show does its own thing.
    /// Only the two that mean the same everywhere are offered here.
    let availableFilters: [EpisodeFilter] = [.downloaded, .favourites]

    func toggle(_ filter: EpisodeFilter) {
        activeFilter = (activeFilter == filter) ? nil : filter
    }

    /// Called as rows appear. Widens the window first, and only goes to the
    /// network once the local rows are used up.
    func loadMoreIfNeeded(currentItem: Podcast) {
        guard !isLoadingMore, !reachedEnd else { return }
        guard let index = visiblePodcasts.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= visiblePodcasts.count - 5 else { return }
        loadMore()
    }

    func loadMore() {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        displayLimit += 20
        let widened = repository.latestPodcasts(limit: displayLimit)

        if widened.count > latestPodcasts.count {
            latestPodcasts = widened
        } else {
            fetchNextPage()
        }
    }

    private func fetchNextPage() {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        nextPage += 1

        podcastService.getPodcasts(for: nil, page: nextPage, date: nil, isBefore: true) { [weak self] result in
            guard let self else { return }
            self.isLoadingMore = false

            switch result {
            case .success(let page):
                if page.podcasts.isEmpty {
                    self.reachedEnd = true
                } else {
                    self.repository.save(page.podcasts.map { Podcast(from: $0) })
                    self.latestPodcasts = self.repository.latestPodcasts(limit: self.displayLimit)
                }
            case .failure(let error):
                self.nextPage -= 1
                AppLog.write(.library, "Error fetching page \(self.nextPage + 1): \(error.localizedDescription)")
            }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        visibility = EpisodeVisibility()
        // Pulling the list down asks the network for new episodes; it should
        // also ask the store for anything another device has sent since.
        repository.refreshFromStore()
        loadCached()
        isLoading = true
        errorMessage = nil
        reachedEnd = false
        nextPage = 1

        podcastService.getPodcasts(for: nil, page: 1, date: nil, isBefore: true) { [weak self] result in
            guard let self else { return }
            self.isLoading = false

            switch result {
            case .success(let page):
                self.repository.save(page.podcasts.map { Podcast(from: $0) })
                self.latestPodcasts = self.repository.latestPodcasts(limit: self.displayLimit)
                // An episode that just landed may be the home of a bookmark
                // caught while it was going out live. This is the moment it
                // becomes possible to say so, and the only one that does not
                // depend on someone opening the right screen.
                BookmarkLibrary.shared.reconcileLiveCaptures()
            case .failure(let error):
                if self.latestPodcasts.isEmpty {
                    self.errorMessage = String(localized: "Nije moguće učitati epizode. Proveri internet vezu.")
                }
                AppLog.write(.library, "Error fetching podcasts: \(error.localizedDescription)")
            }
        }
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

    private func fetchLivestreamUrl() {
        podcastService.getLivestream { [weak self] result in
            switch result {
            case .success(let url):
                DispatchQueue.main.async { self?.livestreamUrl = url }
            case .failure(let error):
                AppLog.write(.library, "Error fetching livestream URL: \(error.localizedDescription)")
            }
        }
    }
}
