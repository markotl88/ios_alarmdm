//
//  RadioView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct RadioView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var viewModel = RadioViewModel()
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        List {
            if isWide {
                Section {
                    Text("Radio")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionSpacing(12)
            }

            // MARK: - Radio uživo
            Section(header: Text("Radio uživo")) {
                // The whole card, not only the mark in its corner. The card is
                // about one thing and the mark says what that is, so anywhere
                // on it means the same press.
                //
                // A button rather than onTapGesture, which the list eats once
                // it has been scrolled: the first press afterwards went to
                // settling the scroll and never reached the card, and the
                // second one worked. A button is wired into the row itself and
                // does not lose that race - and it says it is a button to
                // VoiceOver without being told.
                Button { toggleLive() } label: {
                    liveCard
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel(isLivePlaying ? "Pauziraj radio uživo" : "Pusti radio uživo")
            }

            // MARK: - Podkasti
            Section {
                if viewModel.visiblePodcasts.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.visiblePodcasts, id: \.id) { podcast in
                        PodcastRowView(
                            podcast: podcast,
                            showsMusicVariant: viewModel.showsMusicVariant(for: podcast),
                            isDownloading: viewModel.isDownloading(podcast),
                            isCurrent: playerViewModel.isCurrent(podcast),
                            isPlaying: playerViewModel.isPlaying
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerViewModel.activate(podcast, expandingPlayer: widthClass != .regular)
                            }
                            .episodeRowActions(
                                podcast: podcast,
                                isDownloading: viewModel.isDownloading(podcast),
                                play: { playerViewModel.toggle(podcast) },
                                toggleFavourite: { viewModel.toggleFavourite(podcast) },
                                download: { viewModel.download(podcast) },
                                deleteDownload: { viewModel.deleteDownload(podcast) }
                            )
                            .onAppear { viewModel.loadMoreIfNeeded(currentItem: podcast) }
                    }

                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.canLoadMore && !viewModel.latestPodcasts.isEmpty {
                    Button("Učitaj još epizoda") { viewModel.loadMore() }
                }
            } header: {
                HStack {
                    Text("Najnovije epizode")
                    if let active = viewModel.activeFilter {
                        Spacer()
                        Label(active.title, systemImage: active.systemImage)
                            .textCase(nil)
                            .font(.caption)
                            .foregroundColor(Color("primaryLink"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // A wide page owns its heading so it shares the cards' margins.
        // Text(verbatim:) for the empty one: a bare "" is a
        // LocalizedStringKey, and Xcode kept collecting it into the catalog
        // as a key with no string on either side of it.
        .navigationTitle(isWide ? Text(verbatim: "") : Text("Radio"))
        .navigationBarTitleDisplayMode(isWide ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .refreshable { viewModel.refresh() }
        .onAppear { viewModel.refresh() }
    }

    private var isLivePlaying: Bool {
        playerViewModel.isLive && playerViewModel.isPlaying
    }

    /// True on an iPad, on the Mac, and on a large phone held sideways.
    private var isWide: Bool { widthClass == .regular }

    // MARK: - Radio uživo

    /// Three arrangements of the same card, and which one is used is decided
    /// by how much room the words need before anything else is considered.
    ///
    /// It used to be three bands with nothing in common - the picture, a block
    /// of text on the list background, then a blue bar - and the middle one
    /// was that tall only because the description ran to three lines of copy
    /// worth reading once. The text sits on the picture now and the bar is
    /// gone: what it said is said by a play or pause mark in the corner.
    ///
    /// Except when the words will not fit on a picture at all, which at the
    /// accessibility sizes they will not.
    @ViewBuilder
    private var liveCard: some View {
        if textSize.isAccessibilitySize {
            stackedCard
        } else if isWide {
            sideBySideCard
        } else {
            posterCard
        }
    }

    /// The picture is the card, and the words sit on it.
    ///
    /// Sized by the words rather than cropped to the picture: overlay content
    /// adds nothing to a row's height, so with the height pinned at 230 the
    /// schedule grew downwards from a title that had already been pushed off
    /// the top and clipped away. The picture now fills whatever height the
    /// words ask for, and 230 is only the least it may be.
    private var posterCard: some View {
        HStack(alignment: .bottom, spacing: 12) {
            liveText(onArtwork: true)
            Spacer(minLength: 0)
            transportMark
                .foregroundStyle(.white)
                // The drawing is mostly light blue, and the mark has no plate
                // of its own to sit on.
                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .bottomLeading)
        .background {
            Image("img_radio_wide")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay { artworkScrim }
        }
        .clipped()
    }

    /// The artwork is 3:2. Across the full width of an iPad or a window it
    /// would have to be cropped to a band to keep any sensible height, and
    /// what survives of a drawing cropped that hard is not worth the space it
    /// takes. Beside the text it is shown at its own proportions instead, and
    /// the card stops being a poster and becomes a row.
    private var sideBySideCard: some View {
        HStack(alignment: .center, spacing: 0) {
            // Flexible in height so the picture fills the row when the words
            // make it taller than 200, rather than leaving a band under it.
            Color.clear
                .frame(width: 300)
                .overlay {
                    Image("img_radio_wide")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()

            liveText(onArtwork: false)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

            transportMark
                .foregroundStyle(Color("primary"))
                .padding(.trailing, 24)
        }
        .frame(minHeight: 200)
    }

    /// At the accessibility sizes the words need more room than a picture can
    /// spare, so they stop sharing one: the drawing keeps its height and the
    /// text goes underneath it, where it can be as tall as it needs to be and
    /// is read off the card's own background rather than off a gradient.
    private var stackedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("img_radio_wide")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .clipped()

            HStack(alignment: .top, spacing: 12) {
                liveText(onArtwork: false)
                Spacer(minLength: 0)
                transportMark
                    .foregroundStyle(Color("primary"))
            }
            .padding(16)
        }
    }

    /// Dark enough at the bottom to read white text on a light drawing, and
    /// gone by halfway up so what is underneath is still a picture.
    private var artworkScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0.40),
                .init(color: .black.opacity(0.55), location: 0.72),
                .init(color: .black.opacity(0.88), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    /// The title, and under it either what the station is for or what is
    /// coming out of it.
    ///
    /// A chyron rather than a subtitle once it is playing. The schedule is
    /// worth reading once; the song is worth reading now, and the app already
    /// knows it - the same announcement that goes to the lock screen and to
    /// the car, and which this screen was the only one not to show.
    @ViewBuilder
    private func liveText(onArtwork: Bool) -> some View {
        let heading: Color = onArtwork ? .white : Color("primaryText")
        let supporting: Color = onArtwork ? .white.opacity(0.88) : Color("secondaryText")

        VStack(alignment: .leading, spacing: 5) {
            Text("Internet radio Daško i Mlađa")
                .font(.headline)
                .foregroundStyle(heading)

            if isLivePlaying {
                HStack(spacing: 6) {
                    PulsingLiveDot(size: 7)
                    Text("UŽIVO")
                        .font(.caption.weight(.bold))
                    if let track = playerViewModel.liveTrack {
                        // Long enough to need it, often enough to be worth it:
                        // an announcement is an artist and a title, and the
                        // column here is what is left beside the mark.
                        MarqueeText(text: track.display, font: .subheadline)
                    }
                }
                .foregroundStyle(supporting)
            } else {
                Text("Pon–čet 8–10 h · Varnju radnim danima 11–14 h")
                    .font(.subheadline)
                    .foregroundStyle(supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLivePlaying)
        .animation(.easeInOut(duration: 0.25), value: playerViewModel.liveTrack)
    }

    /// Which way the radio is pointing, and nothing else.
    ///
    /// No circle behind it and no words beside it: the card is the button, and
    /// a filled disc would read as a second, smaller one - the part you are
    /// meant to hit - on a card where anywhere means the same press.
    private var transportMark: some View {
        Image(systemName: isLivePlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 38, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private func toggleLive() {
        playerViewModel.mode = .radio(stream: viewModel.livestreamUrl)
        playerViewModel.togglePlayPause()
    }

    /// The filter lives in the toolbar rather than in a bar under the title.
    /// Chips here would sit directly below the navigation bar once the card
    /// scrolls away - two stacked bars saying the same thing.
    private var filterMenu: some View {
        Menu {
            Toggle("Prikaži preslušane", isOn: settings.showsPlayedEpisodesBinding)
            Divider()
            Picker("Filter", selection: filterBinding) {
                Text("Sve epizode").tag(EpisodeFilter?.none)
                ForEach(viewModel.availableFilters) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(EpisodeFilter?.some(filter))
                }
            }
        } label: {
            Image(systemName: viewModel.activeFilter == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filtriraj epizode")
    }

    private var filterBinding: Binding<EpisodeFilter?> {
        Binding(
            get: { viewModel.activeFilter },
            set: { newValue in withAnimation(.easeInOut(duration: 0.18)) { viewModel.activeFilter = newValue } }
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Učitavanje…").foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } else if let error = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.subheadline).foregroundColor(.secondary)
                Button("Pokušaj ponovo") { viewModel.refresh() }
                    .font(.subheadline)
            }
            .padding(.vertical, 8)
        } else if !viewModel.latestPodcasts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nijedna epizoda ne odgovara filteru.")
                Button("Prikaži sve") {
                    viewModel.activeFilter = nil
                    settings.showsPlayedEpisodes = true
                }
            }
        } else {
            Text("Nema epizoda za prikaz.")
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
    }
}




