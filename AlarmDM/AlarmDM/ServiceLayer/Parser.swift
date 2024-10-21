//
//  Parser.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import Foundation

// XML Parser
class PodcastParser: NSObject {
    
    var currentParsedElement = String()
    var podcasts = [Podcast]()
    var currentPodcast: Podcast!
    var title = ""
    var subtitle = ""
    var timestamp = ""
    var parent = ""
    var itunesDuration = ""

    internal func parse(data: Data) -> [Podcast] {
        podcasts.removeAll()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return podcasts
    }
}

extension PodcastParser: XMLParserDelegate {
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        
        currentParsedElement = elementName
        switch elementName {
        case "item":
            parent = "item"
            currentPodcast = Podcast()
        case "title":
            title = ""
        case "description":
            subtitle = ""
        case "pubDate":
            timestamp = ""
        case "enclosure":
            if let podcastUrl = attributeDict["url"] {
                currentPodcast.podcastUrl = podcastUrl
            }
            if let lengthStr = attributeDict["length"], let length = Double(lengthStr) {
                currentPodcast.lengthInBytes = length
            }
        case "itunes:duration":
            itunesDuration = ""
        default:
            break;
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if parent == "item" {
            switch currentParsedElement {
            case "title":
                title += string
                currentPodcast.title = title
            case "description":
                subtitle += string
                currentPodcast.subtitle = subtitle
            case "pubDate":
                timestamp += string
                currentPodcast.timestamp = timestamp
            case "itunes:duration":
                itunesDuration += string
                currentPodcast.itunesDuration = itunesDuration
            default:
                break;
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        
        switch elementName {
        case "item":
            parent = ""
            podcasts.append(currentPodcast)
        case "pubDate":
            break
            /*
            if let timestamp = currentPodcast.timestamp {
                currentPodcast.createdDate = timestamp.getCreationDate()
            }*/
        default:
            break;
        }
        currentParsedElement = ""
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        NSLog("Podcast parsing over")
    }
}

// Helper extension to convert timestamp string to Date
extension String {
    func getCreationDate() -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z" // Adjust according to the date format of your RSS feed
        return dateFormatter.date(from: self)
    }
}
