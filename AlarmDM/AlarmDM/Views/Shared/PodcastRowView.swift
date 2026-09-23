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
    /// drawing the glyph below - the row does not decide anything about
    /// playback.
    var isCurrent: Bool = false
    var isPlaying: Bool = false

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

                    if showsMusicVariant && !podcast.isWithMusic {
                        Image(systemName: Podcast.withoutMusicSymbol)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Bez muzike")
                    }
                }

                Text(podcast.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                if let progress = podcast.listeningProgress {
                    ListeningProgressLine(progress: progress,
                                          remaining: podcast.remainingDescription)
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)

            // Not a button, a statement: this row plays, and this one is
            // the one playing. A control inside a control is one thing too
            // many on a screen that is also a touch screen, and everything it
            // could do the row already does.
            if widthClass == .regular {
                Image(systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color("primaryLink"))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color("primaryLink").opacity(isCurrent ? 0.20 : 0.10)))
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
            }

            // A fixed column, so the badges cannot push the glyph sideways:
            // a row with a download mark and a row without it put it in the
            // same place.
            VStack(spacing: 6) {
                if podcast.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(Color("secondaryText"))
                        .accessibilityLabel("Odslušano")
                }
                if podcast.isFavorite && !EpisodeRowActions.showsInlineActions {
                    Image(systemName: "heart.fill")
                        .font(.footnote)
                        .foregroundColor(Color("primaryLink"))
                        .accessibilityLabel("Omiljeno")
                }
                if isDownloading && !EpisodeRowActions.showsInlineActions {
                    DownloadProgressRing(podcastId: podcast.id)
                } else if podcast.isDownloaded && !EpisodeRowActions.showsInlineActions {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Preuzeto")
                }
            }
            .frame(width: EpisodeRowActions.showsInlineActions ? (podcast.isPlayed ? 22 : 0) : 22)
        }
        .padding(.vertical, 6)
        // Translucent rather than a colour of its own, so it tints whatever
        // the list is drawing underneath - the Radio tab's grouped cards and
        // the episode list's plain rows both come out right without either
        // screen having to say anything.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color("primaryLink").opacity(podcast.isPlayed ? 0.07 : 0))
                .padding(.horizontal, -8)
        )
    }
}

/// What is left of an episode that was started and not finished: a short bar
/// and the time still in front of you, the way the Podcasts app puts it.
///
/// The bar used to run the width of the row, which at two points tall read as
/// a rule under the text rather than as a measure of anything. Sixty points is
/// enough to see a position in, and what it gives up is space for the one
/// number that answers the question actually being asked.
struct ListeningProgressLine: View {
    let progress: Double
    var remaining: String?

    private let barWidth: CGFloat = 60

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.quaternaryLabel))
                Capsule()
                    .fill(Color("primaryLink"))
                    .frame(width: barWidth * min(max(progress, 0), 1))
            }
            .frame(width: barWidth, height: 3)

            if let remaining {
                Text(remaining)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let heard = String(localized: "Odslušano \(Int(progress * 100)) posto")
        guard let remaining else { return heard }
        return "\(heard), \(remaining.lowercased())"
    }
}

/// A ring that fills as the episode downloads. It subscribes to the library's
/// progress stream and filters for one episode, so a download redraws its own
/// row and nothing else - the list itself only hears about start and finish.
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
