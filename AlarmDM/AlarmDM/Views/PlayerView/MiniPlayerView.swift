//
//  MiniPlayerView.swift
//  AlarmDM
//
//  The bar above the tab bar. Reads the same PlayerViewModel as the full
//  screen player it expands into, which mirrors PlaybackEngine.shared —
//  so what shows here is what is actually coming out of the speakers, whether
//  it was started on the phone, from CarPlay or from the lock screen.
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var widthClass

    private var isWide: Bool { widthClass == .regular }

    /// The bar is sized for a thumb on a phone. On a bigger screen it is
    /// being read from further away and clicked rather than tapped, so it
    /// grows a little — but only a little, since the point of it is still
    /// that it is not the player.
    /// Including the two point strip along the top. The root view reserves
    /// exactly this much space above the tab bar, so the number lives here
    /// rather than being written down twice and drifting apart.
    static func height(for widthClass: UserInterfaceSizeClass?) -> CGFloat {
        (widthClass == .regular ? 72 : 58) + 2
    }

    private var barHeight: CGFloat { isWide ? 72 : 58 }
    private var artworkSide: CGFloat { isWide ? 56 : 44 }
    private var controlSide: CGFloat { isWide ? 40 : 34 }

    var body: some View {
        VStack(spacing: 0) {
            // The bar always ends in a 2pt strip so its height never changes: the
            // episode's progress for a podcast, a plain rule for live radio. A
            // brand-coloured rule across the full width would read as a
            // finished episode.
            if playerViewModel.isLive {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 2)
            } else {
                ProgressView(value: playerViewModel.playbackProgress)
                    .progressViewStyle(.linear)
                    .tint(Color("primaryLink"))
                    .frame(height: 2)
            }

            HStack(spacing: 12) {
                Image(playerViewModel.artworkName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artworkSide, height: artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    // One line that moves, like a chyron, rather than two that
                    // change the bar's height depending on the episode.
                    MarqueeText(
                        text: playerViewModel.title,
                        font: isWide ? .body.weight(.semibold) : .subheadline.weight(.semibold)
                    )
                    .foregroundColor(Color("primaryText"))

                    // Live gets the pulsing dot and a label that scrolls when
                    // the announced track is too long for the bar.
                    if playerViewModel.isLive {
                        LiveLabel(
                            track: playerViewModel.liveTrack,
                            isPlaying: playerViewModel.isPlaying
                        )
                    } else {
                        Text(playerViewModel.subtitle)
                            .font(.caption)
                            .foregroundColor(Color("secondaryText"))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    playerViewModel.addBookmark()
                } label: {
                    Image(systemName: playerViewModel.justBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: controlSide - 4, height: controlSide)
                        .foregroundColor(playerViewModel.justBookmarked
                                         ? Color("primaryLink")
                                         : Color("secondaryText"))
                }
                .accessibilityLabel("Zabeleži")

                Button {
                    playerViewModel.togglePlayPause()
                } label: {
                    ZStack {
                        if playerViewModel.isBuffering {
                            ProgressView()
                        } else {
                            Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                        }
                    }
                    .frame(width: controlSide, height: controlSide)
                    .foregroundColor(Color("primaryText"))
                }
                .accessibilityLabel(playerViewModel.isPlaying ? "Pauziraj" : "Pusti")

                Button {
                    playerViewModel.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: controlSide - 4, height: controlSide)
                        .foregroundColor(Color("secondaryText"))
                }
                .accessibilityLabel("Zaustavi")
            }
            .padding(.horizontal, isWide ? 16 : 12)
            .frame(height: barHeight)
            // Held to the same width as the lists above it, so the artwork
            // starts where the rows start instead of floating off to one side
            // of a wide window.
            .frame(maxWidth: RootView.contentWidth(for: widthClass))
            .frame(maxWidth: .infinity)
        }
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { playerViewModel.isExpanded = true }
        }
    }
}
