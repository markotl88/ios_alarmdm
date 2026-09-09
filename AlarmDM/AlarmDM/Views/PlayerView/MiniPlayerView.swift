//
//  MiniPlayerView.swift
//  AlarmDM
//
//  The bar above the tab bar, and the full screen player it expands into.
//  Both read a single PlayerViewModel, which mirrors PlaybackEngine.shared —
//  so what shows here is what is actually coming out of the speakers, whether
//  it was started on the phone, from CarPlay or from the lock screen.
//

import SwiftUI

// MARK: - Mini player

struct MiniPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !playerViewModel.isLive {
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

                    Text(playerViewModel.isLive ? "UŽIVO" : playerViewModel.subtitle)
                        .font(.caption)
                        .foregroundColor(playerViewModel.isLive ? Color("primaryLink") : Color("secondaryText"))
                        .lineLimit(1)
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

// MARK: - Full screen player

struct FullscreenPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var dragOffset: CGFloat = 0
    @State private var scrubTime: TimeInterval?

    private var displayedTime: TimeInterval {
        scrubTime ?? playerViewModel.currentTime
    }

    var body: some View {
        VStack(spacing: 0) {
            handle

            Spacer(minLength: 8)

            Image(playerViewModel.artworkName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12, y: 6)
                .padding(.horizontal, 32)

            VStack(spacing: 6) {
                Text(playerViewModel.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(Color("primaryText"))
                    .multilineTextAlignment(.center)

                Text(playerViewModel.subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color("secondaryText"))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if playerViewModel.isLive {
                liveBadge.padding(.top, 20)
            } else {
                scrubber.padding(.top, 20)
            }

            transportControls.padding(.top, 20)

            if !playerViewModel.isLive {
                HStack(spacing: 28) {
                    favouriteControl
                    downloadControl
                }
                .padding(.top, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("background").ignoresSafeArea())
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        withAnimation { playerViewModel.isExpanded = false }
                    }
                    withAnimation { dragOffset = 0 }
                }
        )
    }

    private var handle: some View {
        HStack {
            Button {
                withAnimation { playerViewModel.isExpanded = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundColor(Color("secondaryText"))
                    .padding(12)
            }
            .accessibilityLabel("Zatvori plejer")

            Spacer()
        }
        .padding(.top, 8)
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text("UŽIVO").font(.caption.weight(.bold))
        }
        .foregroundColor(Color("primaryText"))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color("primaryLink").opacity(0.18)))
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(playerViewModel.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let target = scrubTime {
                        playerViewModel.seek(to: target)
                        scrubTime = nil
                    }
                }
            )
            .tint(Color("primaryLink"))
            .disabled(playerViewModel.duration <= 0)

            HStack {
                Text(Self.format(displayedTime))
                Spacer()
                Text(Self.format(playerViewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(Color("secondaryText"))
        }
        .padding(.horizontal, 32)
    }

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button {
                playerViewModel.skipBackward()
            } label: {
                Image(systemName: "gobackward.15").font(.title2)
            }
            .disabled(playerViewModel.isLive)

            Button {
                playerViewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(Color("primaryLink")).frame(width: 72, height: 72)
                    if playerViewModel.isBuffering {
                        ProgressView().tint(Color(.systemBackground))
                    } else {
                        Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Color(.systemBackground))
                    }
                }
            }
            .accessibilityLabel(playerViewModel.isPlaying ? "Pauziraj" : "Pusti")

            Button {
                playerViewModel.skipForward()
            } label: {
                Image(systemName: "goforward.15").font(.title2)
            }
            .disabled(playerViewModel.isLive)
        }
        .foregroundColor(Color("primaryText"))
    }

    private var favouriteControl: some View {
        Button {
            playerViewModel.toggleFavourite()
        } label: {
            Label(
                playerViewModel.isFavorite ? "U omiljenim" : "Omiljeno",
                systemImage: playerViewModel.isFavorite ? "heart.fill" : "heart"
            )
            .font(.subheadline)
            .foregroundColor(playerViewModel.isFavorite ? Color("primaryLink") : Color("primaryText"))
        }
        .accessibilityLabel(playerViewModel.isFavorite ? "Ukloni iz omiljenih" : "Dodaj u omiljene")
    }

    @ViewBuilder
    private var downloadControl: some View {
        if playerViewModel.isDownloading {
            VStack(spacing: 8) {
                ProgressView(value: playerViewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(Color("primaryLink"))
                    .frame(width: 180)
                Text("Preuzimanje \(Int(playerViewModel.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(Color("secondaryText"))
            }
        } else if playerViewModel.showCheckmark {
            Label("Preuzeto", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.green)
        } else if playerViewModel.isDownloaded {
            Button(role: .destructive) {
                playerViewModel.deletePodcast()
            } label: {
                Label("Obriši preuzeto", systemImage: "trash")
                    .font(.subheadline)
            }
        } else {
            Button {
                playerViewModel.downloadPodcast()
            } label: {
                Label("Preuzmi epizodu", systemImage: "arrow.down.circle")
                    .font(.subheadline)
            }
            .foregroundColor(Color("primaryLink"))
        }
    }

    private static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "--:--" }
        let total = Int(time)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
