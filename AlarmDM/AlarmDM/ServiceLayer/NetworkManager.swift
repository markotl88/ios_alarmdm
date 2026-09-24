//
//  NetworkManager.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case download = ""
}

enum NetworkError: Error {
    case urlEncodingFailed(url: String)
    case urlNotValid(url: String)
    case responseNotValid
    case dataNotValid
    case dataError
    case decodingError(message: String?)
    case encodingError
    case urlError(statusCode: Int)
    case serverError(statusCode: Int)
    case unknown
    case authenticationError
}

protocol NetworkManaging {
    func performRequest(url: String, httpMethod: HTTPMethod, completion: @escaping (Result<Data, Error>) -> Void)
    func performRequest<T: Decodable>(url: URL, httpMethod: HTTPMethod, headers: [String: String]?, body: Encodable?, completion: @escaping (Result<T, Error>) -> Void)
    func get<T: Codable>(url: URL, headers: [String: String]?, completion: @escaping (Result<T, Error>) -> ())
    func downloadFile(from url: URL, completion: @escaping (Result<URL, Error>) -> Void, progressHandler: @escaping (Double) -> Void)
}

final class NetworkManager: NetworkManaging {
    let session: URLSession
    
    private enum Constants {
        static let timeoutIntervalForRequest: TimeInterval = 15
        static let timeoutIntervalForResource: TimeInterval = 180
    }

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // URLSession.configuration returns a copy; configure before creation.
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Constants.timeoutIntervalForRequest
            configuration.timeoutIntervalForResource = Constants.timeoutIntervalForResource
            self.session = URLSession(configuration: configuration)
        }
    }
    
    func performRequest(url: String, httpMethod: HTTPMethod, completion: @escaping (Result<Data, any Error>) -> Void) {
        
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            completion(.failure(NetworkError.urlEncodingFailed(url: url)))
            return
        }

        guard let url = URL(string: encodedUrl) else {
            completion(.failure(NetworkError.urlNotValid(url: encodedUrl)))
            return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = httpMethod.rawValue
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(NetworkError.responseNotValid))
                return
            }
            switch response.statusCode {
            case 200...299:
                break
            default:
                completion(.failure(NetworkError.serverError(statusCode: response.statusCode)))
                return
            }
            guard let data = data else {
                completion(.failure(NetworkError.dataNotValid))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }
    
    func get<T>(url: URL, headers: [String: String]? = nil, completion: @escaping (Result<T, Error>) -> ()) where T: Codable {
        
        var request = URLRequest(url: url)
        
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            // Handle error
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            // Verify HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    break // Successful response
                case 401:
                    DispatchQueue.main.async {
                        completion(.failure(NetworkError.authenticationError))
                    }
                    return
                default:
                    DispatchQueue.main.async {
                        completion(.failure(NetworkError.serverError(statusCode: httpResponse.statusCode)))
                    }
                    return
                }
            }
            
            // Handle missing data
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NetworkError.dataError))
                }
                return
            }
            
            do {
                // Decode the data into the expected type
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(decodedData))
                }
            } catch let error {
                DispatchQueue.main.async {
                    completion(.failure(NetworkError.decodingError(message: error.localizedDescription)))
                }
            }
        }
        task.resume()
    }
    
    func performRequest<T>(url: URL, httpMethod: HTTPMethod, headers: [String : String]?, body: (any Encodable)?, completion: @escaping (Result<T, any Error>) -> Void) where T : Decodable {
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 60
        urlRequest.httpMethod = httpMethod.rawValue
        
        if let headers = headers {
            for (key, value) in headers {
                urlRequest.addValue(value, forHTTPHeaderField: key)
            }
        }
        
        if let body = body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            do {
                let encodedData = try encoder.encode(body)
                urlRequest.httpBody = encodedData
            } catch {
                completion(.failure(NetworkError.encodingError))
                return
            }
        }
        
        let task = session.dataTask(with: urlRequest) { data, urlResponse, error in
            if let error = error as? URLError {
                switch error.code {
                default:
                    completion(.failure(NetworkError.urlError(statusCode: error.code.rawValue)))
                }
            }
            
            if let error = error {
                completion(.failure(error))
            }
            
            if let urlResponse = urlResponse as? HTTPURLResponse {
                switch urlResponse.statusCode {
                case 200...299:
                    break
                case 401, 403:
                    completion(.failure(NetworkError.authenticationError))
                    return
                default:
                    completion(.failure(NetworkError.serverError(statusCode: urlResponse.statusCode)))
                    return
                }
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.dataError))
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decodedData = try decoder.decode(T.self, from: data)
                completion(.success(decodedData))
            } catch {
                completion(.failure(NetworkError.decodingError(message: nil)))
            }

            
        }
        task.resume()
    }

    func downloadFile(from url: URL, completion: @escaping (Result<URL, Error>) -> Void, progressHandler: @escaping (Double) -> Void) {
        let downloadTask = session.downloadTask(with: url) { localURL, response, error in
            // Handle errors
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    completion(.failure(NetworkError.dataNotValid))
                }
                return
            }

            do {
                // Move file to a permanent location
                let fileManager = FileManager.default
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                let destinationURL = documentsURL?.appendingPathComponent(url.lastPathComponent)

                if let destinationURL = destinationURL {
                    // If the file already exists, remove it before copying the new file
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }

                    try fileManager.moveItem(at: localURL, to: destinationURL)

                    // Downloaded episodes are re-downloadable content: keep them out of
                    // iCloud backups (App Store review flags apps that back up caches).
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = true
                    var mutableURL = destinationURL
                    try? mutableURL.setResourceValues(resourceValues)

                    DispatchQueue.main.async {
                        completion(.success(destinationURL))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NetworkError.dataError))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }

        // Observe progress updates
        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                progressHandler(progress.fractionCompleted)
            }
        }
        
        // Start the download task
        downloadTask.resume()
        
        // Make sure to invalidate the observation **after** the task is complete, not immediately
        downloadTask.progress.cancellationHandler = {
            observation.invalidate() // Safely invalidate the observation when download completes
        }
    }}

extension URLRequest {
    /// What was asked for and where. `debugPrint(self)` used to print the
    /// request object, which says almost nothing; a method and an address say
    /// the whole thing in one line.
    @discardableResult
    public func debugLog() -> Self {
        AppLog.write(.network, "\(httpMethod ?? "GET") \(url?.absoluteString ?? "bez adrese")")
        return self
    }
}
