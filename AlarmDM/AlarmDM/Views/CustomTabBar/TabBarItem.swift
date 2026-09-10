//
//  TabBarItem.swift
//  TestTabBar2
//
//  Created by Marko Stajic on 31.10.2024.
//

import Foundation
import SwiftUI

enum TabBarItem: Hashable {
    case radio, shows, support, settings
    
    var title: String {
        switch self {
        case .radio: return "Radio"
        case .shows: return "Emisije"
        case .support: return "Podrži"
        case .settings: return "Ostalo"
        }
    }

    var iconName: String {
        switch self {
        case .radio: return "dot.radiowaves.left.and.right"
        case .shows: return "music.note.list"
        case .support: return "heart"
        case .settings: return "gearshape"
        }
    }
    
    var color: Color {
        switch self {
        case .radio: return .blue
        case .shows: return .green
        case .support: return .orange
        case .settings: return .yellow
        }
    }
}
