//
//  ContentViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI
import RealmSwift

final class ContentViewModel: ObservableObject {
    
    @Published var podcasts: [Podcast] = [] // This can contain both Podcasts and Placeholders
    @Published var errorMessage: String?
    @Published var isLoadingMore: Bool = false
    
    private let podcastService: PodcastServiceProtocol
    private var currentPage = 1
    private var totalPages: Int = 1
    private let realm = try! Realm()
    
    init(podcastService: PodcastServiceProtocol = PodcastService()) {
        self.podcastService = podcastService
    }
    
    // MARK: - Fetch Podcasts from Server and Save to Realm
    func fetchData() {
        podcasts = loadPodcastsFromRealm()
        
        if let lastDate = podcasts.first?.createdDate?.iso8601String {
            debugPrint("Last date: \(lastDate)")
            getPodcasts(from: lastDate, isBefore: false)
        } else {
            getPodcasts(from: nil, isBefore: true)
        }
    }
    
    // MARK: - Fetch Podcasts from Realm
    private func loadPodcastsFromRealm() -> [Podcast] {
        let podcastRealms = realm.objects(PodcastRealm.self).sorted(byKeyPath: "createdAt", ascending: false)
        return podcastRealms.map { Podcast(from: $0) }
    }
    
    private func getPodcasts(from date: String?, isBefore: Bool?) {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        podcastService.getPodcasts(page: currentPage, date: date, isBefore: isBefore) { [weak self] result in
            guard let self else { return }
            self.isLoadingMore = false
            switch result {
            case .success(let paginationData):
                
                let newRealmPodcasts = paginationData.podcasts.map { PodcastRealm(from: $0) }
                self.savePodcastsToRealm(newRealmPodcasts)
                self.podcasts = loadPodcastsFromRealm()
                
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func savePodcastsToRealm(_ newPodcasts: [PodcastRealm]) {
        try! realm.write {
            for podcast in newPodcasts {
                realm.add(podcast, update: .modified)
            }
        }
    }
    
    // MARK: - Fetch More Data if Needed
    func fetchDataIfNeeded(currentItem: Podcast?) {
        guard let currentItem = currentItem else { return }
        guard !isLoadingMore else { return }
        
        if currentPage <= totalPages, let date = currentItem.createdDate?.iso8601String {
            getPodcasts(from: date, isBefore: true)
        }
    }
}
