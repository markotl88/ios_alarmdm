//
//  ContentViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import Foundation

final class ContentViewModel: ObservableObject {
    
    @Published var podcasts: [Podcast] = []
    @Published var errorMessage: String?
    @Published var isLoadingMore: Bool = false
    
    private let podcastService: PodcastServiceProtocol
    private var currentPage = 1
    private var totalPages: Int = 1
    
    init(podcastService: PodcastServiceProtocol = PodcastService()) {
        self.podcastService = podcastService
    }
    
    func fetchData() {
        guard !isLoadingMore else { return } // Prevent multiple fetches
        isLoadingMore = true
        debugPrint("Fetching data")

        podcastService.getPodcasts(page: currentPage) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
                switch result {
                case .success(let paginationData):
                    self?.podcasts.append(contentsOf: paginationData.podcasts)
                    self?.currentPage += 1
                    self?.totalPages = paginationData.totalPages
                    debugPrint("Total pages: \(paginationData.totalPages)")
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func fetchDataIfNeeded(currentItem: Podcast?) {
        guard let currentItem = currentItem else {
            return
        }
        guard !isLoadingMore else {
            debugPrint("Multiple fetch")
            return
        } // Prevent multiple fetches

        if currentPage <= totalPages {
            fetchData()
        }
    }
}

