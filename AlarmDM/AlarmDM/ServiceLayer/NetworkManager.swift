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
}

final class NetworkManager: NetworkManaging {
    let session: URLSession
    
    private enum Constants {
        static let timeoutIntervalForRequest: TimeInterval = 15
        static let timeoutIntervalForResource: TimeInterval = 180
    }

    init(session: URLSession = URLSession.shared) {
        self.session = session
        self.session.configuration.timeoutIntervalForRequest = Constants.timeoutIntervalForRequest
        self.session.configuration.timeoutIntervalForResource = Constants.timeoutIntervalForResource
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
    
    func get<T>(url: URL, headers: [String: String]? = nil, completion: @escaping (Result<T, Error>) -> ()) where T : Codable {
        
        var request = URLRequest(url: url)
        
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            // Handle error
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Verify HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    break // Successful response
                case 401:
                    completion(.failure(NetworkError.authenticationError))
                    return
                default:
                    completion(.failure(NetworkError.serverError(statusCode: httpResponse.statusCode)))
                    return
                }
            }
            
            // Handle missing data
            guard let data = data else {
                completion(.failure(NetworkError.dataError))
                return
            }
            
            do {
                // Decode the data into the expected type
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decodedData))
            } catch let error {
                completion(.failure(NetworkError.decodingError(message: error.localizedDescription)))
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

}

extension URLRequest {
    public func debugLog() -> Self {
        debugPrint(self)
        return self
    }
}

