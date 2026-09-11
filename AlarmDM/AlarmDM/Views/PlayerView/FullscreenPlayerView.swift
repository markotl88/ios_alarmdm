//
//  FullscreenPlayerView.swift
//  AlarmDM
//
//  The player the mini bar expands into. Everything here reads the same
//  PlayerViewModel, so the two can never disagree about what is playing.
//

import SwiftUI
import AVKit

struct FullscreenPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var dragOffset: CGFloat = 0

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

            actionRow.padding(.top, 24)

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

    /// The badge, and under it whatever the station says is playing. The label
    /// only appears when the stream actually announces a track — an empty line
    /// reserved "just in case" would push the layout around every time radio
    /// starts.
    private var liveBadge: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                PulsingLiveDot(isAnimating: playerViewModel.isPlaying)
                Text("UŽIVO").font(.caption.weight(.bold))
            }
            .foregroundColor(Color("primaryText"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color("primaryLink").opacity(0.18)))

            if let track = playerViewModel.liveTrack {
                VStack(spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color("primaryText"))
                    if let artist = track.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(Color("secondaryText"))
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 32)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playerViewModel.liveTrack)
    }

    private var scrubber: some View {
        ScrubberView(
            currentTime: playerViewModel.currentTime,
            duration: playerViewModel.duration,
            onSeek: { playerViewModel.seek(to: $0) }
        )
        .padding(.horizontal, 32)
    }

    private var transportControls: some View {
        HStack(spacing: 40) {
            // Live radio has nothing to skip through. A dimmed control still
            // invites a tap; leaving it out says what is going on.
            if !playerViewModel.isLive {
                Button {
                    playerViewModel.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15").font(.title2)
                }
            }

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

            if !playerViewModel.isLive {
                Button {
                    playerViewModel.skipForward()
                } label: {
                    Image(systemName: "goforward.15").font(.title2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playerViewModel.isLive)
        .foregroundColor(Color("primaryText"))
    }

    /// Icon-only, evenly sized: favourite, download, output — and the bookmark
    /// button will join them. Labels under every one would crowd the screen and
    /// say what the glyphs already say. Live radio has nothing to favourite or
    /// download, so only the output picker remains.
    private var actionRow: some View {
        HStack(spacing: 20) {
            if !playerViewModel.isLive {
                favouriteControl
                downloadControl
            }
            routeControl
        }
        .animation(.easeInOut(duration: 0.2), value: playerViewModel.isLive)
    }

    private var favouriteControl: some View {
        PlayerActionButton(
            label: playerViewModel.isFavorite ? "Ukloni iz omiljenih" : "Dodaj u omiljene",
            action: { playerViewModel.toggleFavourite() }
        ) {
            Image(systemName: playerViewModel.isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundColor(playerViewModel.isFavorite ? Color("primaryLink") : Color("primaryText"))
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        if playerViewModel.isDownloading {
            // The ring carries the percentage the caption used to spell out.
            PlayerActionButton(label: "Preuzimanje u toku", action: {}) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: max(playerViewModel.progress, 0.02))
                        .stroke(Color("primaryLink"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color("secondaryText"))
                }
            }
            .disabled(true)
        } else if playerViewModel.showCheckmark {
            PlayerActionButton(label: "Preuzeto", action: {}) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
            .disabled(true)
        } else if playerViewModel.isDownloaded {
            PlayerActionButton(label: "Obriši preuzeto", action: { playerViewModel.deletePodcast() }) {
                Image(systemName: "trash")
                    .font(.title3)
                    .foregroundColor(.red)
            }
        } else {
            PlayerActionButton(label: "Preuzmi epizodu", action: { playerViewModel.downloadPodcast() }) {
                Image(systemName: "arrow.down")
                    .font(.title3)
                    .foregroundColor(Color("primaryText"))
            }
        }
    }

    /// Apple's own picker: AirPods, the car stereo, an AirPlay speaker. It draws
    /// its own glyph and presents the system sheet, and it turns blue by itself
    /// when the sound is going somewhere other than the phone.
    private var routeControl: some View {
        RoutePickerView(
            tintColor: UIColor(named: "primaryText") ?? .label,
            activeTintColor: UIColor(named: "primaryLink") ?? .systemBlue
        )
        .frame(width: 30, height: 30)
        .frame(width: 52, height: 52)
        .background(Circle().fill(Color(.tertiarySystemFill)))
        .accessibilityLabel("Izlaz zvuka")
    }

}

// MARK: - Shared action button

/// One shape for every action under the transport controls, so the row reads as
/// a set rather than as three unrelated buttons.
private struct PlayerActionButton<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Output picker

/// AVRoutePickerView has no SwiftUI equivalent. Volume stays on the hardware
/// buttons — a slider here would only duplicate them and steal room.
struct RoutePickerView: UIViewRepresentable {
    let tintColor: UIColor
    let activeTintColor: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = tintColor
        view.activeTintColor = activeTintColor
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}

// MARK: - Scrubber

/// Plain @State bound straight to the Slider, on purpose.
///
/// It used to be a computed Binding — `scrubTime ?? currentTime` to read, the
/// dragged value into `scrubTime` to write — and after one drag the slider
/// stopped following playback until the player was minimised, which is when
/// that state was destroyed. So something wrote the dragged value back after
/// the gesture handler had cleared it. With no setter of our own there is
/// nothing left to call out of order.
///
/// It lives in its own view for the second half of it: the player above
/// redraws every second as the time advances, and the less of that reaches a
/// live gesture the better. Incoming times are ignored entirely while a drag
/// is in flight rather than fighting it for the value.
struct ScrubberView: View {

    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var value: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $value, in: 0...max(duration, 1)) { editing in
                isScrubbing = editing
                if !editing { onSeek(value) }
            }
            .tint(Color("primaryLink"))
            .disabled(duration <= 0)

            HStack {
                Text(Self.format(value))
                Spacer()
                Text(Self.format(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(Color("secondaryText"))
        }
        .onAppear { value = currentTime }
        .onChange(of: currentTime) { _, new in
            guard !isScrubbing else { return }
            value = new
        }
    }

    static func format(_ time: TimeInterval) -> String {
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
