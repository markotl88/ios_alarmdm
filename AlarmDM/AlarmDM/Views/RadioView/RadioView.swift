//
//  RadioView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct RadioView: View {
    @StateObject private var viewModel = RadioViewModel()
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var widthClass

    var body: some View {
        List {
            // MARK: - Radio uživo
            Section(header: Text("Radio uživo")) {
                liveCard
                    .listRowInsets(EdgeInsets())
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
                            isDownloading: viewModel.isDownloading(podcast)
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerViewModel.mode = .podcast(podcast: podcast)
                                playerViewModel.togglePlayPause()
                            }
                            .episodeRowActions(
                                podcast: podcast,
                                isDownloading: viewModel.isDownloading(podcast),
                                play: {
                                    playerViewModel.mode = .podcast(podcast: podcast)
                                    playerViewModel.togglePlayPause()
                                },
                                toggleFavourite: { viewModel.toggleFavourite(podcast) },
                                download: { viewModel.download(podcast) },
                                deleteDownload: { viewModel.deleteDownload(podcast) }
                            )
                            .onAppear { viewModel.loadMoreIfNeeded(currentItem: podcast) }
                    }

                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Najnoviji podkasti")
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
        .navigationTitle("Radio")
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

    /// Stacked on a phone, side by side once there is room.
    ///
    /// The artwork is 3:2. Across the full width of an iPad or a window it
    /// would have to be cropped to a band to keep any sensible height, and
    /// what survives of a drawing cropped that hard is not worth the space it
    /// takes. Beside the text it is shown at its own proportions instead, and
    /// the card stops being a poster and becomes a row.
    @ViewBuilder
    private var liveCard: some View {
        if isWide {
            HStack(alignment: .top, spacing: 0) {
                Image("img_radio_wide")
                    .resizable()
                    .aspectRatio(3 / 2, contentMode: .fill)
                    .frame(width: 300, height: 200)
                    .clipped()

                VStack(alignment: .leading, spacing: 12) {
                    liveText
                    Spacer(minLength: 0)
                    liveButton
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Image("img_radio_wide")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()

                liveText
                    .padding(16)

                liveButton
            }
        }
    }

    private var liveText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Internet radio Daško i Mlađa")
                .font(.headline)
            Text("Alarm od 8h do 10h, Varnju od 11h, dobra muzika non-stop!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liveButton: some View {
        Button {
            playerViewModel.mode = .radio(stream: viewModel.livestreamUrl)
            playerViewModel.togglePlayPause()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isLivePlaying ? "pause.fill" : "play.fill")
                Text(isLivePlaying ? "Pauziraj radio uživo" : "Pusti radio uživo")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color("primary"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLivePlaying ? "Pauziraj radio uživo" : "Pusti radio uživo")
    }

    /// The filter lives in the toolbar rather than in a bar under the title.
    /// Chips here would sit directly below the navigation bar once the card
    /// scrolls away — two stacked bars saying the same thing.
    private var filterMenu: some View {
        Menu {
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
        } else {
            Text("Nema podkasta za prikaz.")
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
    }
}




