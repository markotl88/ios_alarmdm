//
//  TabContentViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import Foundation

class TabContentViewModel: ObservableObject {
    @Published var selectedTab: Tab = .radio
    
    enum Tab {
        case radio, contact, store, settings
    }
}
