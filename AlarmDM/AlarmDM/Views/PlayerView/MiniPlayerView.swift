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

    /// Including the two point strip along the top. The root view reserves
    /// exactly this much space above the tab bar, so the number lives here
    /// rather than being written down twice and drifting apart.
    static func height(for widthClass: UserInterfaceSizeClass?) -> CGFloat {
        (widthClass == .regular ? 84 : 58) + 2
    }

    // The bar is sized for a thumb on a phone. On a Mac or an iPad it is read
    // from further away and clicked rather than tapped, and it now runs the
    // whole width of the window — a phone-sized strip across a metre of glass
    // looks like something left behind. Everything in it grows together;
    // scaling the bar and not its contents is what makes a control look lost.

    private var barHeight: CGFloat { isWide ? 84 : 58 }
    private var artworkSide: CGFloat { isWide ? 64 : 44 }
    private var controlSide: CGFloat { isWide ? 46 : 34 }
    private var titleFont: Font { isWide ? .title3.weight(.semibold) : .subheadline.weight(.semibold) }
    private var subtitleFont: Font { isWide ? .subheadline : .caption }
    private var sideControlFont: Font { isWide ? .title3.weight(.semibold) : .subheadline.weight(.semibold) }

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
                    .scaleEffect(x: 1, y: isWide ? 1.5 : 1, anchor: .top)
            }

            HStack(spacing: isWide ? 16 : 12) {
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
                        font: titleFont
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
                            .font(subtitleFont)
                            .foregroundColor(Color("secondaryText"))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    playerViewModel.addBookmark()
                } label: {
                    Image(systemName: playerViewModel.justBookmarked ? "bookmark.fill" : "bookmark")
                        .font(sideControlFont)
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
                                .font(isWide ? .title : .title3)
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
                        .font(sideControlFont)
                        .frame(width: controlSide - 4, height: controlSide)
                        .foregroundColor(Color("secondaryText"))
                }
                .accessibilityLabel("Zaustavi")
            }
            .padding(.horizontal, isWide ? 24 : 12)
            .frame(height: barHeight)
        }
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { playerViewModel.isExpanded = true }
        }
    }
}
