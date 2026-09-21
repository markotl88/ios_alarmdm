//
//  PodcastEpisodesView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct PodcastEpisodesView: View {

    @StateObject private var viewModel: PodcastEpisodesViewModel
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var widthClass

    /// Owns its view model. It used to be created inline in ShowListView's body and
    /// held with @ObservedObject, so every re-render threw away the fetched episodes.
    init(show: Show) {
        _viewModel = StateObject(wrappedValue: PodcastEpisodesViewModel(show: show))
    }

    var body: some View {
        Group {
            if viewModel.podcasts.isEmpty {
                emptyState
            } else {
                episodeList
            }
        }
        .navigationTitle(viewModel.showTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.fetchData() }
    }

    private var episodeList: some View {
        VStack(spacing: 0) {
            filterBar

            List {
                ForEach(viewModel.visiblePodcasts) { podcast in
                    PodcastRowView(
                        podcast: podcast,
                        showsMusicVariant: viewModel.hasBothMusicVariants,
                        isDownloading: viewModel.isDownloading(podcast),
                        isCurrent: playerViewModel.isCurrent(podcast),
                        isPlaying: playerViewModel.isPlaying
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playerViewModel.activate(podcast, expandingPlayer: widthClass != .regular)
                        }
                        .onAppear {
                            if podcast == viewModel.podcasts.last {
                                viewModel.fetchDataIfNeeded(currentItem: podcast)
                            }
                        }
                        .episodeRowActions(
                            podcast: podcast,
                            isDownloading: viewModel.isDownloading(podcast),
                            play: { playerViewModel.toggle(podcast) },
                            toggleFavourite: { viewModel.toggleFavourite(podcast) },
                            download: { viewModel.download(podcast) },
                            deleteDownload: { viewModel.deleteDownload(podcast) }
                        )
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { viewModel.fetchData() }
            .overlay {
                if viewModel.visiblePodcasts.isEmpty && !viewModel.podcasts.isEmpty {
                    filteredEmptyState
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableFilters) { filter in
                    let isActive = viewModel.activeFilter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { viewModel.toggle(filter) }
                    } label: {
                        Label(filter.title, systemImage: filter.systemImage)
                            .font(.footnote.weight(isActive ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    isActive ? Color("primaryLink") : Color(.tertiarySystemFill)
                                )
                            )
                            // System background as the foreground: white on blue in
                            // light mode, near-black on light blue in dark mode.
                            .foregroundColor(isActive ? Color(.systemBackground) : Color("primaryText"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color("background"))
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Nijedna epizoda ne odgovara filteru.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Prikaži sve") {
                withAnimation { viewModel.activeFilter = nil }
            }
            .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("background"))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if viewModel.isLoadingMore {
                ProgressView()
                Text("Učitavanje epizoda…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "waveform.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(viewModel.errorMessage ?? String(localized: "Nema epizoda za ovu emisiju."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Pokušaj ponovo") { viewModel.fetchData() }
                    .font(.subheadline)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
