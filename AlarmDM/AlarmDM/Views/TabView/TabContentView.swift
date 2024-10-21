//
//  TabView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct TabContentView: View {
    @StateObject private var tabViewModel = TabContentViewModel()
    
    var body: some View {
        TabView(selection: $tabViewModel.selectedTab) {
            RadioView()
                .tabItem {
                    Image(systemName: "radio.fill")
                    Text("Radio")
                }
                .tag(TabContentViewModel.Tab.radio)
            
            ContentView(viewModel: ContentViewModel.init())
                .tabItem {
                    Image(systemName: "paperplane.fill")
                    Text("Kontakt")
                }
                .tag(TabContentViewModel.Tab.contact)
            
            StoreView()
                .tabItem {
                    Image(systemName: "cart.fill")
                    Text("Prodavnica")
                }
                .tag(TabContentViewModel.Tab.store)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Ostalo")
                }
                .tag(TabContentViewModel.Tab.settings)
        }
    }
}

#Preview {
    TabContentView()
}
