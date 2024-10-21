//
//  PodcastService.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import Foundation

enum APIRouter: String {
    case webshop = "https://daskoimladja.bigcartel.com/"
    case livestream = "http://172.105.250.193:8000/stream"
    case podcasts = "http://podcast.daskoimladja.com/feed.xml"
    case phoneNumber = "+38166442266"
    case bankAccount = "325-9300600398707-66"
    case firebasePodcasts = "https://getpodcasts-ysnuoqfipq-uc.a.run.app"
    
    static func getPodcasts(page: Int? = nil, pageSize: Int = 200) -> String {
        guard let page = page else {
            return APIRouter.firebasePodcasts.rawValue + "?pageSize=\(pageSize)"
        }
        return APIRouter.firebasePodcasts.rawValue + "?page=\(page)&pageSize=\(pageSize)"
    }
}

struct Podcast: Codable, Identifiable, Equatable {
    var id: String = ""
    var title = ""
    var subtitle = ""
    var timestamp: String?
    var podcastUrl = ""
    var duration = ""
    var lengthInBytes = 0.0
    var itunesDuration = ""
    var fileUrl = ""
    var isFavorite = false
    var isDownloaded = false
    var withMusic = false
    var createdDate: String? // Change to String
}

extension Podcast {
    var formattedCreatedDate: Date? {
        guard let createdDate = createdDate else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z" // Use the correct format for your date
        return dateFormatter.date(from: createdDate)
    }
}

protocol PodcastServiceProtocol {
    func getPodcasts(page: Int?, completion: @escaping (Result<PaginationDataResponse<Podcast>, Error>) -> Void)
}

final class PodcastService: PodcastServiceProtocol {
    
    private let networkManager: NetworkManaging
    
    init(networkManager: NetworkManaging = NetworkManager()) {
        self.networkManager = networkManager
    }
    
    func getPodcasts(page: Int? = nil, completion: @escaping (Result<PaginationDataResponse<Podcast>, Error>) -> Void) {
        let endpoint = APIRouter.getPodcasts(page: page)
        guard let url = URL(string: endpoint) else {
            completion(.failure(NetworkError.urlNotValid(url: endpoint))) // Handle invalid URL case
            return
        }
        
        networkManager.get(url: url, headers: nil, completion: completion)
    }
}

// MARK: - PaginationData
struct PaginationDataResponse<T: Codable>: Codable {
    let page: Int
    let pageSize: Int
    let totalItems: Int
    let totalPages: Int
    let podcasts: [T]
}
