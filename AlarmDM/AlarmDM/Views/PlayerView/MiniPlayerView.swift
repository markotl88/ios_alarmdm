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
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(playerViewModel.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color("primaryText"))
                        .lineLimit(1)

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
                    .frame(width: 34, height: 34)
                    .foregroundColor(Color("primaryText"))
                }
                .accessibilityLabel(playerViewModel.isPlaying ? "Pauziraj" : "Pusti")

                Button {
                    playerViewModel.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 34)
                        .foregroundColor(Color("secondaryText"))
                }
                .accessibilityLabel("Zaustavi")
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
        }
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { playerViewModel.isExpanded = true }
        }
    }
}
