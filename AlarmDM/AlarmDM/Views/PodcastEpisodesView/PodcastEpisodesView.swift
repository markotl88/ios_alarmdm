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
                    PodcastRowView(podcast: podcast, showsMusicVariant: viewModel.hasBothMusicVariants)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playerViewModel.mode = .podcast(podcast: podcast)
                            playerViewModel.togglePlayPause()
                        }
                        .onAppear {
                            if podcast == viewModel.podcasts.last {
                                viewModel.fetchDataIfNeeded(currentItem: podcast)
                            }
                        }
                        .episodeRowActions(
                            podcast: podcast,
                            play: {
                                playerViewModel.mode = .podcast(podcast: podcast)
                                playerViewModel.togglePlayPause()
                            },
                            toggleFavourite: { viewModel.toggleFavourite(podcast) },
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
                                    isActive ? Color("primary") : Color("primary").opacity(0.10)
                                )
                            )
                            .foregroundColor(isActive ? .white : Color("primaryText"))
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
                Text(viewModel.errorMessage ?? "Nema epizoda za ovu emisiju.")
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

// Separate View for each podcast row
/// Shared by the Radio tab and the episode list.
struct PodcastRowView: View {
    let podcast: Podcast
    /// Only true inside a show that publishes both cuts, so the badge means
    /// something instead of appearing on every row.
    var showsMusicVariant: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(podcast.show.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(podcast.title)
                        .font(.headline)
                        .lineLimit(2)

                    if showsMusicVariant {
                        Image(systemName: podcast.isWithMusic ? "music.note" : "music.note.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel(podcast.isWithMusic ? "Sa muzikom" : "Bez muzike")
                    }
                }

                Text(podcast.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                if podcast.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.footnote)
                        .foregroundColor(Color("primary"))
                        .accessibilityLabel("Omiljeno")
                }
                if podcast.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Preuzeto")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 20)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 20)
        }
        .padding()
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Color.white
                    .mask(
                        Rectangle()
                            .fill(
                                LinearGradient(gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0), location: phase),
                                    .init(color: Color.white.opacity(0.5), location: phase + 0.1),
                                    .init(color: Color.white.opacity(0), location: phase + 0.2)
                                ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .rotationEffect(.degrees(30))
                    )
                    .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
            )
            .onAppear {
                phase = -0.5
                DispatchQueue.main.async {
                    withAnimation {
                        phase = 1.5
                    }
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerEffect())
    }
}

// MARK: - Row actions

/// Swipe and long press carry the same actions. Swipe is fast for anyone who
/// knows it is there; the context menu is how everyone else finds it, which is
/// the same pairing Apple's own Podcasts app uses.
struct EpisodeRowActions: ViewModifier {
    let podcast: Podcast
    let play: () -> Void
    let toggleFavourite: () -> Void
    let deleteDownload: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleFavourite()
                } label: {
                    Label(
                        podcast.isFavorite ? "Ukloni" : "Omiljeno",
                        systemImage: podcast.isFavorite ? "heart.slash" : "heart"
                    )
                }
                .tint(Color("primary"))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if podcast.isDownloaded {
                    Button(role: .destructive) {
                        deleteDownload()
                    } label: {
                        Label("Obriši", systemImage: "trash")
                    }
                }
            }
            .contextMenu {
                Button {
                    play()
                } label: {
                    Label("Pusti", systemImage: "play.fill")
                }

                Button {
                    toggleFavourite()
                } label: {
                    Label(
                        podcast.isFavorite ? "Ukloni iz omiljenih" : "Dodaj u omiljene",
                        systemImage: podcast.isFavorite ? "heart.slash" : "heart"
                    )
                }

                if podcast.isDownloaded {
                    Button(role: .destructive) {
                        deleteDownload()
                    } label: {
                        Label("Obriši preuzeto", systemImage: "trash")
                    }
                }
            }
    }
}

extension View {
    func episodeRowActions(
        podcast: Podcast,
        play: @escaping () -> Void,
        toggleFavourite: @escaping () -> Void,
        deleteDownload: @escaping () -> Void
    ) -> some View {
        modifier(EpisodeRowActions(
            podcast: podcast,
            play: play,
            toggleFavourite: toggleFavourite,
            deleteDownload: deleteDownload
        ))
    }
}
