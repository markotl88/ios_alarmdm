//
//  TabView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct TabContentView: View {
    @StateObject private var tabViewModel = TabContentViewModel()
    let bindingFalse = Binding.constant(false)
    
    var body: some View {
        TabView(selection: $tabViewModel.selectedTab) {
            RadioView()
                .tabItem {
                    Image(systemName: "radio.fill")
                    Text("Radio")
                }
                .tag(TabContentViewModel.Tab.radio)
            
            ShowView()
                .tabItem {
                    Image(systemName: "radio.fill")
                    Text("Podkast")
                }
                .tag(TabContentViewModel.Tab.radio)

            StoreView()
                .tabItem {
                    Image(systemName: "paperplane.fill")
                    Text("Podkast")
                }
                .tag(TabContentViewModel.Tab.contact) // Fix the tag to match the correct view
            
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
        .accentColor(Color("primary"))  // Set the accent color for the TabView
        .background(Color("background"))  // Set the background color
        .onAppear {
            UITabBar.appearance().barTintColor = UIColor(named: "background") // Customize tab bar background
        }
    }
}

#Preview {
    TabContentView()
}
