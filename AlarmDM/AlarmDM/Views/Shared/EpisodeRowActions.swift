//
//  EpisodeRowActions.swift
//  AlarmDM
//
//  Swipe and long press on an episode row, in one place so the Radio tab and
//  a show's list cannot drift apart.
//

import SwiftUI

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

    static var showsInlineActions: Bool {
        ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if Self.showsInlineActions {
            // Siblings of the tappable row: these buttons must not start playback.
            HStack(spacing: 8) {
                content
                inlineActions
            }
        } else {
            touchActions(content: content)
        }
    }

    private var inlineActions: some View {
        HStack(spacing: 8) {
            Button(action: toggleFavourite) {
                actionIcon(podcast.isFavorite ? "heart.fill" : "heart")
            }
            .help(podcast.isFavorite ? Text("Ukloni iz omiljenih") : Text("Dodaj u omiljene"))
            .accessibilityLabel(podcast.isFavorite ? Text("Ukloni iz omiljenih") : Text("Dodaj u omiljene"))

            if isDownloading {
                DownloadProgressRing(podcastId: podcast.id)
                    .frame(width: 32, height: 32)
                    .help(Text("Preuzimanje u toku…"))
            } else {
                Button(action: podcast.isDownloaded ? deleteDownload : download) {
                    actionIcon(podcast.isDownloaded ? "trash" : "arrow.down.circle")
                }
                .help(podcast.isDownloaded ? Text("Obriši preuzeto") : Text("Preuzmi epizodu"))
                .accessibilityLabel(podcast.isDownloaded ? Text("Obriši preuzeto") : Text("Preuzmi epizodu"))
            }
        }
        .buttonStyle(.borderless)
    }

    private func actionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Color("primaryLink"))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color("primaryLink").opacity(0.10)))
            .contentShape(Circle())
    }

    private func touchActions(content: Content) -> some View {
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
