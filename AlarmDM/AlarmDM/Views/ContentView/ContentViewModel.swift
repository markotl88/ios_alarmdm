//
//  ContentViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI
import RealmSwift

final class ContentViewModel: ObservableObject {
    
    @Published var podcasts: [Podcast] = []
    @Published var errorMessage: String?
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreData: Bool = true
    
    private let podcastService: PodcastServiceProtocol
    private let selectedShow: Show
    private var currentPage = 1
    private var totalPages: Int = 1
    private let realm = try! Realm()
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
        let podcastRealms = realm.objects(PodcastRealm.self)
            .filter("show == %@", selectedShow.rawValue)
            .sorted(byKeyPath: "createdAt", ascending: false)
        return podcastRealms.map { Podcast(from: $0) }
    }
    
    
    private func getPodcasts(for show: String?, from date: String?, isBefore: Bool?) {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        podcastService.getPodcasts(for: show, page: currentPage, date: date, isBefore: isBefore) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMore = false
            switch result {
            case .success(let paginationData):
                
                let newRealmPodcasts = paginationData.podcasts.map { PodcastRealm(from: $0) }
                self.savePodcastsToRealm(newRealmPodcasts)
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
    
    private func savePodcastsToRealm(_ newPodcasts: [PodcastRealm]) {
        try! realm.write {
            newPodcasts.forEach { realm.add($0, update: .modified)}
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
