//
//  LiveIndicatorViews.swift
//  AlarmDM
//
//  The two pieces that say "this is happening right now": a dot that breathes
//  while the stream is playing, and a label that scrolls only when what the
//  station announced does not fit.
//

import SwiftUI

// MARK: - Pulsing dot

struct PulsingLiveDot: View {

    var size: CGFloat = 8
    /// Paused radio gets a still dot. A pulse on a stopped stream would be
    /// telling the person something that is not true.
    var isAnimating: Bool = true

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { isAnimating && !reduceMotion }

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: size, height: size)
            .scaleEffect(pulsing && active ? 1.0 : 0.7)
            .opacity(pulsing && active ? 1.0 : 0.5)
            .animation(
                active
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing && active
            )
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Marquee

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Scrolls its text only when the text does not fit - a short title stays
/// still, which is what most of them do.
///
/// It travels like a chyron rather than a conveyor: out to the end of the
/// text, pause, back to the start, pause. A looping belt of two copies reads
/// faster than it moves and never lets you finish a long title, because the
/// beginning has already gone by the time you reach the end.
struct MarqueeText: View {

    let text: String
    var font: Font = .caption
    /// Slow on purpose. The eye is following words, not watching a marquee.
    var pointsPerSecond: Double = 16
    /// Long enough to read the end before it starts back.
    var pause: Double = 1.5

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var travel: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far past the edge the text runs. Only this much has to move - the
    /// rest is already on screen.
    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    private var scrolls: Bool {
        !reduceMotion && containerWidth > 0 && overflow > 1
    }

    var body: some View {
        // A blank line of the right font is what the layout is built on, and
        // the text rides in an overlay. Overlay content never widens its
        // parent: a long title with .fixedSize() proposes a width far past the
        // screen, and `clipped()` only hides the drawing - by then the bar, and
        // everything around it, has already been stretched.
        Text(verbatim: " ")
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                label.offset(x: offset)
            }
            .clipped()
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: MarqueeWidthKey.self, value: geometry.size.width)
                }
            )
            .onPreferenceChange(MarqueeWidthKey.self) { width in
                guard width != containerWidth else { return }
                containerWidth = width
                restart()
            }
            .onChange(of: text) { _, _ in restart() }
            // The two measurements arrive in no fixed order. Without this, a
            // width that lands after the container's would leave `scrolls`
            // reading false forever and the text would never move.
            .onChange(of: textWidth) { _, _ in restart() }
            .onDisappear { travel?.cancel() }
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { textWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, new in textWidth = new }
                }
            )
    }

    /// Back to the start without animating, then out and back for as long as
    /// the view is on screen. Without the transaction the reset itself would
    /// animate, and the text would slide backwards across the bar every time
    /// the song changed.
    private func restart() {
        travel?.cancel()

        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }

        guard scrolls else { return }

        let distance = overflow
        // A floor on the duration, so a title that only just overflows does
        // not twitch instead of travelling.
        let duration = max(1.2, Double(distance) / pointsPerSecond)

        travel = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: duration)) { offset = -distance }

                try? await Task.sleep(for: .seconds(duration + pause))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: duration)) { offset = 0 }

                try? await Task.sleep(for: .seconds(duration))
            }
        }
    }
}

// MARK: - Live label

/// The dot plus whatever there is to say. With no announced track it is just
/// the word, which on its own is still the point: this is live.
struct LiveLabel: View {

    let track: LiveTrack?
    var isPlaying: Bool = true
    var font: Font = .caption
    var textColor: Color = Color("secondaryText")

    private var text: String {
        guard let track else { return String(localized: "UŽIVO") }
        return String(localized: "UŽIVO · \(track.display)")
    }

    var body: some View {
        HStack(spacing: 6) {
            PulsingLiveDot(isAnimating: isPlaying)
            MarqueeText(text: text, font: font)
                .foregroundColor(textColor)
        }
    }
}
