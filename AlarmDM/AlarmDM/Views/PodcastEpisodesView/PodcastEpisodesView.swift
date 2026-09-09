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
        List {
            ForEach(viewModel.podcasts) { podcast in
                PodcastRowView(podcast: podcast)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(podcast.show.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(podcast.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if podcast.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Preuzeto")
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
