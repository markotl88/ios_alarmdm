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

    /// The bookmark confirmation lives here too, so it shows wherever the
    /// capture came from — the player, and later the car.
    @State private var capturedBookmark: Bookmark?
    /// Set the moment the toast is touched. Typing a note takes longer than
    /// the countdown, and having it close mid-word would be worse than not
    /// offering the field at all.
    @State private var toastHeld = false

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

            // Above the full screen player too. The bookmark button is right
            // there, and a confirmation you have to close the player to see is
            // not a confirmation.
            if let bookmark = capturedBookmark {
                VStack {
                    Spacer()
                    BookmarkToastView(
                        bookmark: bookmark,
                        onCategory: { category in
                            BookmarkLibrary.shared.setCategory(category, for: bookmark.id)
                            dismissToast()
                        },
                        onNote: { note in
                            BookmarkLibrary.shared.setNote(note, for: bookmark.id)
                        },
                        onInteract: { toastHeld = true },
                        onDismiss: dismissToast
                    )
                    .id(bookmark.id)
                    .padding(.bottom, toastBottomInset)
                }
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerViewModel.isExpanded)
        .environmentObject(playerViewModel)
        .onReceive(BookmarkLibrary.shared.didCapture) { bookmark in
            toastHeld = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                capturedBookmark = bookmark
            }
            // Long enough to reach for a category, short enough not to sit on
            // top of the player. A second capture replaces the first, and the
            // id check keeps the older timer from closing the newer toast.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                guard capturedBookmark?.id == bookmark.id, !toastHeld else { return }
                dismissToast()
            }
        }
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

    /// Sits just above whatever is at the bottom at that moment: the tab bar,
    /// the mini player on top of it, or nothing at all when the full screen
    /// player is covering both.
    private var toastBottomInset: CGFloat {
        guard !playerViewModel.isExpanded else { return 32 }
        let miniPlayer: CGFloat = playerViewModel.isPresented ? 60 : 0
        return 60 + miniPlayer + 8
    }

    private func dismissToast() {
        toastHeld = false
        withAnimation(.easeInOut(duration: 0.2)) { capturedBookmark = nil }
    }
}
