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
    case firebasePodcasts = "https://us-central1-dasko-i-mladja.cloudfunctions.net/getPodcasts"
    
    var url: String {
        self.rawValue
    }
}

extension String {
    var formattedCreatedDate: Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ" // Format for ISO 8601 date with milliseconds
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // Use POSIX locale to ensure consistency
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Use UTC timezone for "Z"
        return dateFormatter.date(from: self)
    }
}

extension Date {
    var iso8601String: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] // Ensure milliseconds are included
        return isoFormatter.string(from: self)
    }
}
protocol PodcastServiceProtocol {
    func getPodcasts(for show: String?, page: Int?, date: String?, isBefore: Bool?, completion: @escaping (Result<PaginationDataResponse<PodcastResponse>, Error>) -> Void)
}

final class PodcastService: PodcastServiceProtocol {
    private let networkManager: NetworkManaging
    
    init(networkManager: NetworkManaging = NetworkManager()) {
        self.networkManager = networkManager
    }
    
    func getPodcasts(for show: String?, page: Int? = nil, date: String?, isBefore: Bool?, completion: @escaping (Result<PaginationDataResponse<PodcastResponse>, any Error>) -> Void) {
        
        let address = APIRouter.firebasePodcasts.url
        var components = URLComponents(string: address)
        
        var queryItems = [URLQueryItem]()
        if let show = show {
            queryItems.append(URLQueryItem(name: "show", value: show))
        }
        if let page = page {
            queryItems.append(URLQueryItem(name: "page", value: String(page)))
        }
        if let date = date {
            queryItems.append(URLQueryItem(name: "date", value: date))
        }
        if let isBefore = isBefore {
            queryItems.append(URLQueryItem(name: "is_before", value: String(isBefore)))
        }
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            completion(.failure(NetworkError.urlNotValid(url: address)))
            return
        }
        
        networkManager.get(url: url, headers: nil, completion: completion)
    }
}

// MARK: - PaginationData
struct PaginationDataResponse<T: Codable>: Codable {
    let page: Int?
    let pageSize: Int?
    let totalItems: Int
    let totalPages: Int?
    let podcasts: [T]
}
