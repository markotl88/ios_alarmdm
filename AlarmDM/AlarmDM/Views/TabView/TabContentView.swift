//
//  TabView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct NewTabContentView: View {
    @State private var currentItem: TabBarItem = .radio
    @StateObject private var playerViewModel = PlayerViewModel(mode: nil)

    /// The WiFi-only warning lives here rather than in each list, so the same
    /// alert answers a blocked download wherever it was started — a row, the
    /// player, either tab.
    @State private var blockedEpisode: Podcast?
    @State private var showsMeteredAlert = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                switch currentItem {
                case .radio:
                    NavigationStack {
                        RadioView()
                    }
                case .shows:
                    NavigationStack {
                        ShowView()
                    }
                case .support:
                    NavigationStack {
                        SupportView()
                    }
                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                }

                // rezerviši prostor za MiniPlayer + TabBar
                Spacer().frame(height: playerViewModel.isPresented && !playerViewModel.isExpanded ? 60 : 0)
                Spacer().frame(height: 60) // fiksna visina lažnog tab bara
            }

            VStack(spacing: 0) {
                Spacer()

                if playerViewModel.isPresented && !playerViewModel.isExpanded {
                    MiniPlayerView()
                        .environmentObject(playerViewModel)
                }
                
                if !playerViewModel.isExpanded {
                    TabBar(currentItem: $currentItem)
                }
            }

            if playerViewModel.isExpanded {
                FullscreenPlayerView()
                    .environmentObject(playerViewModel)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerViewModel.isExpanded)
        .environmentObject(playerViewModel)
        .onReceive(EpisodeLibrary.shared.downloadBlocked) { podcast in
            blockedEpisode = podcast
            showsMeteredAlert = true
        }
        .alert("Preuzimanje samo preko WiFi-ja", isPresented: $showsMeteredAlert) {
            Button("Preuzmi svejedno") {
                if let blockedEpisode { EpisodeLibrary.shared.download(blockedEpisode, force: true) }
            }
            Button("Isključi ograničenje") {
                AppSettings.shared.downloadsOverWiFiOnly = false
                if let blockedEpisode { EpisodeLibrary.shared.download(blockedEpisode) }
            }
            Button("Otkaži", role: .cancel) { blockedEpisode = nil }
        } message: {
            Text("Trenutno si na mobilnoj mreži. Možeš preuzeti samo ovu epizodu, ili ukloniti ograničenje za ubuduće - kasnije ga vraćaš u Ostalo.")
        }
    }
}

struct TabBar: View {
    @Binding var currentItem: TabBarItem

    var body: some View {
        HStack {
            tabButton(item: .radio)
            Spacer()
            tabButton(item: .shows)
            Spacer()
            tabButton(item: .support)
            Spacer()
            tabButton(item: .settings)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemBackground).ignoresSafeArea(edges: .bottom))
        .foregroundColor(Color.primary)
        .font(.footnote)
    }

    @ViewBuilder
    private func tabButton(item: TabBarItem) -> some View {
        Button(action: {
            currentItem = item
        }) {
            VStack(spacing: 4) {
                Image(systemName: item.iconName)
                    .font(.system(size: 20, weight: currentItem == item ? .semibold : .regular))
                Text(item.title)
            }
            .foregroundColor(currentItem == item ? Color.accentColor : Color.secondary)
        }
    }
}
