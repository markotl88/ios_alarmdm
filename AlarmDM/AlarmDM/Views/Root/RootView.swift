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
    @Environment(\.horizontalSizeClass) private var widthClass

    /// How wide the content is allowed to get before it stops following the
    /// window. A list of episode titles set to the full width of a Mac window
    /// is a line of text with a hundred points of subject and eight hundred of
    /// nothing, and an eye has to travel all of it. Everything that scrolls
    /// keeps to this, and so does the mini player, so the two line up.
    static func contentWidth(for widthClass: UserInterfaceSizeClass?) -> CGFloat {
        widthClass == .regular ? 900 : .infinity
    }

    /// The WiFi-only warning lives here rather than in each list, so the same
    /// alert answers a blocked download wherever it was started — a row, the
    /// player, either tab.
    @State private var blockedEpisode: Podcast?
    @State private var showsMeteredAlert = false

    /// The bookmark confirmation lives here too, so it shows wherever the
    /// capture came from — the player, and later the car.
    @State private var capturedBookmark: Bookmark?
    @State private var capturedFromPhone = true
    /// Set the moment the toast is touched. Typing a note takes longer than
    /// the countdown, and having it close mid-word would be worse than not
    /// offering the field at all.
    @State private var toastHeld = false

    var body: some View {
        ZStack {
            // The content column stops at nine hundred points, but the page it
            // sits on does not. Without this the window shows white margins on
            // either side of a grey list, which reads as a panel floating on
            // nothing rather than as a column of content on a page.
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            shell

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
                        asksForNote: capturedFromPhone,
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
        .onReceive(BookmarkLibrary.shared.didCapture) { capture in
            let bookmark = capture.bookmark
            toastHeld = false
            capturedFromPhone = capture.origin == .phone
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
            if phase != .active {
                playerViewModel.rememberPlaybackPosition()
            } else {
                // Coming back is the other moment something may have arrived
                // from another device — the import often lands while the app
                // was away, and nothing else would notice until the next
                // launch.
                playerViewModel.catchUpIfIdle()
            }
        }
    }

    private var isWide: Bool { widthClass == .regular }

    // MARK: - The shell

    /// Two shapes for the same four screens. A phone gets the tab bar along
    /// the bottom; anything wider gets them down the side, where an iPad and a
    /// Mac both expect to find navigation — and where the empty half of a wide
    /// window turns into something useful rather than a margin.
    @ViewBuilder
    private var shell: some View {
        if isWide {
            wideShell
        } else {
            compactShell
        }
    }

    private var wideShell: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            screen
                .frame(maxWidth: RootView.contentWidth(for: widthClass))
                .frame(maxWidth: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        // Across the whole window, under the sidebar as well. What is playing
        // does not belong to the section you happen to be looking at — it
        // keeps playing while you move between all four — so the bar anchors
        // the window rather than one column of it. As a safe area inset rather
        // than an overlay, so the list above it scrolls to its own end instead
        // of underneath.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playerViewModel.isPresented && !playerViewModel.isExpanded {
                MiniPlayerView()
                    .environmentObject(playerViewModel)
            }
        }
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            ForEach(TabBarItem.ordered, id: \.self) { item in
                Label(item.title, systemImage: item.iconName)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Daško i Mlađa")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The sidebar wants to be able to select nothing; this app never does.
    private var sidebarSelection: Binding<TabBarItem?> {
        Binding(
            get: { currentItem },
            set: { selected in
                if let selected { currentItem = selected }
            }
        )
    }

    private var compactShell: some View {
        ZStack {
            VStack(spacing: 0) {
                screen

                // rezerviši prostor za MiniPlayer + TabBar
                Spacer().frame(height: playerViewModel.isPresented && !playerViewModel.isExpanded
                               ? MiniPlayerView.height(for: widthClass)
                               : 0)
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
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch currentItem {
        case .radio:
            NavigationStack { RadioView() }
        case .shows:
            NavigationStack { ShowView() }
        case .support:
            NavigationStack { SupportView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }

    /// Sits just above whatever is at the bottom at that moment: the tab bar,
    /// the mini player on top of it, or nothing at all when the full screen
    /// player is covering both. On a wide window there is no tab bar to clear.
    private var toastBottomInset: CGFloat {
        guard !playerViewModel.isExpanded else { return 32 }
        let miniPlayer = playerViewModel.isPresented ? MiniPlayerView.height(for: widthClass) : 0
        let tabBar: CGFloat = isWide ? 0 : 60
        return tabBar + miniPlayer + 8
    }

    private func dismissToast() {
        toastHeld = false
        withAnimation(.easeInOut(duration: 0.2)) { capturedBookmark = nil }
    }
}
