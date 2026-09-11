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

/// Scrolls its text only when the text is wider than the space it was given —
/// a short title stays still, which is what most of them do. Two copies with a
/// gap between them make the loop seamless: by the time the first has left, the
/// second is already in place.
struct MarqueeText: View {

    let text: String
    var font: Font = .caption
    /// Slow enough to read at a glance on a bar 44 points tall.
    var pointsPerSecond: Double = 26
    var gap: CGFloat = 40

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scrolls: Bool {
        !reduceMotion && textWidth > containerWidth + 1 && containerWidth > 0
    }

    var body: some View {
        // A blank line of the right font is what the layout is built on, and
        // the text rides in an overlay. Overlay content never widens its
        // parent, which is the whole problem: two copies of a long title with
        // .fixedSize() propose a width far past the screen, and `clipped()`
        // only hides the drawing — the bar, and everything around it, had
        // already been stretched by then.
        Text(verbatim: " ")
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if scrolls {
                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .offset(x: offset)
                } else {
                    label
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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
            // reading false forever and the loop would never start.
            .onChange(of: textWidth) { _, _ in restart() }
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

    /// Jumps back to the start without animating, then begins the loop. Without
    /// the transaction the reset itself would animate, and the text would slide
    /// backwards across the bar every time the song changed.
    private func restart() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }

        guard scrolls else { return }

        let distance = textWidth + gap
        withAnimation(.linear(duration: distance / pointsPerSecond).repeatForever(autoreverses: false)) {
            offset = -distance
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
        guard let track else { return "UŽIVO" }
        return "UŽIVO · \(track.display)"
    }

    var body: some View {
        HStack(spacing: 6) {
            PulsingLiveDot(isAnimating: isPlaying)
            MarqueeText(text: text, font: font)
                .foregroundColor(textColor)
        }
    }
}
