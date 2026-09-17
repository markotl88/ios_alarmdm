//
//  PodcastRowView.swift
//  AlarmDM
//
//  One episode in a list. Shared by the Radio tab and by a show's episodes,
//  so it lives here rather than inside either screen.
//

import SwiftUI

/// Shared by the Radio tab and the episode list.
struct PodcastRowView: View {
    let podcast: Podcast
    /// Only true inside a show that publishes both cuts, so the badge means
    /// something instead of appearing on every row.
    var showsMusicVariant: Bool = false
    var isDownloading: Bool = false
    /// The episode the player is holding, and whether it is running. Only for
    /// drawing the button below — the row does not decide anything about
    /// playback.
    var isCurrent: Bool = false
    var isPlaying: Bool = false
    /// Given only where a button earns its place. Nil leaves the row as it was.
    var onPlay: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var widthClass

    var body: some View {
        HStack(spacing: 12) {
            Image(podcast.show.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .cornerRadius(8)
                .opacity(podcast.isPlayed ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(podcast.title)
                        .font(.headline)
                        // Heard: still legible, no longer competing with the
                        // episodes that have not been.
                        .foregroundColor(podcast.isPlayed ? Color("secondaryText") : Color("primaryText"))
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

                if let progress = podcast.listeningProgress {
                    ListeningProgressLine(progress: progress)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            // A row the width of a Mac window is a large target for one small
            // idea. The button says what the row does without having to be
            // discovered, and gives the one thing a tap on the row no longer
            // does: stop it.
            if let onPlay, widthClass == .regular {
                Button(action: onPlay) {
                    Image(systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color("primaryLink"))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color("primaryLink").opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .accessibilityLabel(isCurrent && isPlaying ? "Pauziraj" : "Pusti")
            }

            VStack(spacing: 6) {
                if podcast.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(Color("secondaryText"))
                        .accessibilityLabel("Odslušano")
                }
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
        // Translucent rather than a colour of its own, so it tints whatever
        // the list is drawing underneath — the Radio tab's grouped cards and
        // the episode list's plain rows both come out right without either
        // screen having to say anything.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color("primaryLink").opacity(podcast.isPlayed ? 0.07 : 0))
                .padding(.horizontal, -8)
        )
    }
}

/// The line under an episode that has been started and not finished. Two
/// capsules rather than a ProgressView: at two points tall, the stock control
/// brings its own padding and its own minimum height, and fights the row.
struct ListeningProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.quaternaryLabel))
                Capsule()
                    .fill(Color("primaryLink"))
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 2)
        .accessibilityLabel("Odslušano \(Int(progress * 100)) posto")
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
