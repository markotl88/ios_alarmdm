//
//  FileService.swift
//  AlarmDM
//
//  Created by Marko Stajic on 23.10.2024.
//

import Foundation

protocol FileServiceProtocol {
    func deleteFile(with fileName: String) -> Result<Bool, FileServiceError>
    func getFile(with fileName: String) -> Result<URL, FileServiceError>
    func downloadedFiles() -> [URL]
    func downloadedBytes() -> Int64
    func deleteAllDownloads() -> Result<Int, FileServiceError>
}

enum FileServiceError: Error {
    case noDocumentsFolder
    case fileNotFound(fileName: String)
    case unknownError(message: String)
}

class FileService: FileServiceProtocol {
    
    private let fileManager = FileManager.default
    
    func deleteFile(with fileName: String) -> Result<Bool, FileServiceError> {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .failure(.noDocumentsFolder)
        }
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                return .success(true)
            } catch let error {
                return .failure(.unknownError(message: error.localizedDescription))
            }
        } else {
            return .failure(.fileNotFound(fileName: fileName))
        }
    }
    
    /// Every episode we have on disk. Downloads land in Documents as .mp3.
    func downloadedFiles() -> [URL] {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let contents = try? fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        return contents.filter { $0.pathExtension.lowercased() == "mp3" }
    }

    func downloadedBytes() -> Int64 {
        downloadedFiles().reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }

    /// Returns how many files were removed.
    func deleteAllDownloads() -> Result<Int, FileServiceError> {
        let files = downloadedFiles()
        var removed = 0
        for url in files {
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                return .failure(.unknownError(message: error.localizedDescription))
            }
        }
        return .success(removed)
    }

    func getFile(with fileName: String) -> Result<URL, FileServiceError> {
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory, in: .userDomainMask).first else {
            return .failure(.noDocumentsFolder)
        }
        
        let fileURL = documentsURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            return .success(fileURL)
        }
        return .failure(.fileNotFound(fileName: fileName))
    }
    
//    func saveDownloadedFile(_ location: URL, to destinationFileName: String) -> URL? {
//        let fileManager = FileManager.default
//        // Get the documents directory URL
//        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
//            print("Error: Documents directory not found.")
//            return nil
//        }
//        
//        let destinationURL = documentsURL.appendingPathComponent(destinationFileName)
//        
//        do {
//            // Ensure the file exists at the temp location
//            if !fileManager.fileExists(atPath: location.path) {
//                print("Error: Temp file doesn't exist at location: \(location.path)")
//                return nil
//            }
//            
//            // If the file already exists in the destination, remove it first
//            if fileManager.fileExists(atPath: destinationURL.path) {
//                try fileManager.removeItem(at: destinationURL)
//            }
//            
//            // Move the file from the temporary location to the documents directory
//            try fileManager.moveItem(at: location, to: destinationURL)
//            return destinationURL
//            
//        } catch {
//            print("Error moving file to Documents directory: \(error.localizedDescription)")
//            return nil
//        }
//    }
}
