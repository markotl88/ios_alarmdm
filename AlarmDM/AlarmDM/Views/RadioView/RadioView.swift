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

    var body: some View {
        List {
            // MARK: - Radio uživo
            Section(header: Text("Radio uživo")) {
                VStack(alignment: .leading, spacing: 0) {
                    Image("img_radio_wide")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Internet radio Daško i Mlađa")
                            .font(.headline)
                        Text("Svakog radnog dana 07-10h. Dobra muzika non-stop!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)

                    Button {
                        playerViewModel.mode = .radio(stream: viewModel.livestreamUrl)
                        playerViewModel.togglePlayPause()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isLivePlaying ? "pause.fill" : "play.fill")
                            Text(isLivePlaying ? "Pauziraj uživo" : "Pusti uživo")
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
                .listRowInsets(EdgeInsets())
            }

            // MARK: - Podkasti
            Section {
                if viewModel.visiblePodcasts.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.visiblePodcasts, id: \.id) { podcast in
                        PodcastRowView(podcast: podcast)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerViewModel.mode = .podcast(podcast: podcast)
                                playerViewModel.togglePlayPause()
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
                podcastsHeader
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Radio")
        .refreshable { viewModel.refresh() }
        .onAppear { viewModel.refresh() }
    }

    private var isLivePlaying: Bool {
        playerViewModel.isLive && playerViewModel.isPlaying
    }

    /// Sticky header: the section title plus the two filters that mean the same
    /// thing across every show. "With music" is left to a show's own list.
    private var podcastsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Najnoviji podkasti")

            HStack(spacing: 8) {
                ForEach(viewModel.availableFilters) { filter in
                    let isActive = viewModel.activeFilter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { viewModel.toggle(filter) }
                    } label: {
                        Label(filter.title, systemImage: filter.systemImage)
                            .font(.caption.weight(isActive ? .semibold : .regular))
                            .textCase(nil)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(isActive ? Color("primary") : Color("primary").opacity(0.12))
                            )
                            .foregroundColor(isActive ? .white : Color("primaryText"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
        }
        .padding(.bottom, 4)
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




