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
                    PodcastRowView(
                        podcast: podcast,
                        showsMusicVariant: viewModel.hasBothMusicVariants,
                        isDownloading: viewModel.isDownloading(podcast)
                    )
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
                            isDownloading: viewModel.isDownloading(podcast),
                            play: {
                                playerViewModel.mode = .podcast(podcast: podcast)
                                playerViewModel.togglePlayPause()
                            },
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
    var isDownloading: Bool = false

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
                        .foregroundColor(Color("primaryLink"))
                        .accessibilityLabel("Omiljeno")
                }
                if isDownloading {
                    DownloadProgressRing(podcastId: podcast.id)
                } else if podcast.isDownloaded {
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

/// A ring that fills as the episode downloads. It subscribes to the library's
/// progress stream and filters for one episode, so a download redraws its own
/// row and nothing else — the list itself only hears about start and finish.
struct DownloadProgressRing: View {
    let podcastId: UUID

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.quaternaryLabel), lineWidth: 2)
            Circle()
                // A hair of the ring is always drawn, so the control reads as
                // "started" rather than as an empty circle in the first seconds.
                .trim(from: 0, to: max(progress, 0.03))
                .stroke(Color("primaryLink"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .animation(.linear(duration: 0.2), value: progress)
        .onAppear { progress = EpisodeLibrary.shared.progress(for: podcastId) }
        .onReceive(EpisodeLibrary.shared.progressPublisher) { update in
            guard update.id == podcastId else { return }
            progress = update.progress
        }
        .accessibilityLabel("Preuzimanje \(Int(progress * 100)) posto")
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
    let isDownloading: Bool
    let play: () -> Void
    let toggleFavourite: () -> Void
    let download: () -> Void
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
                .tint(Color("primaryLink"))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if podcast.isDownloaded {
                    // Deliberately not `role: .destructive`: that role makes
                    // SwiftUI animate the row out as if the episode were gone,
                    // and it then slides back in once the list reloads. Only
                    // the downloaded file goes away, so the row must stay put
                    // and simply swap its badge and its available actions.
                    Button {
                        deleteDownload()
                    } label: {
                        Label("Obriši", systemImage: "trash")
                    }
                    .tint(.red)
                } else if !isDownloading {
                    Button {
                        download()
                    } label: {
                        Label("Preuzmi", systemImage: "arrow.down.circle")
                    }
                    .tint(.gray)
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
                } else if isDownloading {
                    // Disabled rather than hidden: the menu should say why
                    // there is no Preuzmi, instead of silently dropping it.
                    Button {} label: {
                        Label("Preuzimanje u toku…", systemImage: "arrow.down.circle")
                    }
                    .disabled(true)
                } else {
                    Button {
                        download()
                    } label: {
                        Label("Preuzmi epizodu", systemImage: "arrow.down.circle")
                    }
                }
            }
    }
}

extension View {
    func episodeRowActions(
        podcast: Podcast,
        isDownloading: Bool = false,
        play: @escaping () -> Void,
        toggleFavourite: @escaping () -> Void,
        download: @escaping () -> Void,
        deleteDownload: @escaping () -> Void
    ) -> some View {
        modifier(EpisodeRowActions(
            podcast: podcast,
            isDownloading: isDownloading,
            play: play,
            toggleFavourite: toggleFavourite,
            download: download,
            deleteDownload: deleteDownload
        ))
    }
}
