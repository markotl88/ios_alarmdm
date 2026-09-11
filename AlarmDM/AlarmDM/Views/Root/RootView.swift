//
//  RootView.swift
//  AlarmDM
//
//  The app's root: the four tabs, the mini player above them, and the
//  full screen player that slides over everything.
//

import SwiftUI

struct RootView: View {
    @State private var currentItem: TabBarItem = .radio
    @StateObject private var playerViewModel = PlayerViewModel(mode: nil)
    @Environment(\.scenePhase) private var scenePhase

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
        .onAppear { playerViewModel.restorePlaybackState() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving is the last moment anything is certain. iOS can end a
            // suspended app without warning and without calling back, so the
            // position is written down here rather than on the way out.
            if phase != .active { playerViewModel.rememberPlaybackPosition() }
        }
    }
}
