//
//  BookmarkToastView.swift
//  AlarmDM
//
//  What shows up after the bookmark button. The capture already happened —
//  this only offers to say what it was, and goes away on its own if you would
//  rather keep listening.
//

import SwiftUI

struct BookmarkToastView: View {

    let bookmark: Bookmark
    /// Only when the phone is the thing being used. A keyboard rising for a
    /// button pressed in the car helps nobody: the phone is in a cradle or a
    /// pocket, and the sentence gets written later or not at all.
    let asksForNote: Bool
    let onCategory: (BookmarkCategory) -> Void
    let onNote: (String) -> Void
    /// Called the moment the toast is touched, so whoever put it on screen
    /// stops counting down. Typing a note takes longer than five seconds.
    let onInteract: () -> Void
    let onDismiss: () -> Void

    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(bookmark: Bookmark,
         asksForNote: Bool,
         onCategory: @escaping (BookmarkCategory) -> Void,
         onNote: @escaping (String) -> Void,
         onInteract: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.bookmark = bookmark
        self.asksForNote = asksForNote
        self.onCategory = onCategory
        self.onNote = onNote
        self.onInteract = onInteract
        self.onDismiss = onDismiss
        // A live capture arrives with the announced song already in it, which
        // is usually the note you would have written anyway.
        _note = State(initialValue: bookmark.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            noteField

            categories
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill")
                .font(.footnote)
                .foregroundColor(Color("primaryLink"))

            Text("Zabeleženo na \(bookmark.positionText)")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color("primaryText"))

            Spacer(minLength: 0)

            Button(action: finish) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color("secondaryText"))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zatvori")
        }
    }

    /// The one moment you know what you just heard. A line of text here saves
    /// scrolling through a list of episode titles later, wondering which of
    /// the four bookmarks in the same episode was which.
    private var noteField: some View {
        TextField("O čemu se radi?", text: $note)
            .font(.subheadline)
            .textFieldStyle(.plain)
            .focused($noteFocused)
            .submitLabel(.done)
            .onChange(of: noteFocused) { _, focused in
                if focused { onInteract() }
            }
            .onSubmit(finish)
            .onAppear {
                // A live capture with nothing announced has no content of its
                // own - no position in an episode, no song title. Whatever gets
                // typed here is the only thing that row will ever say, so the
                // field asks for it instead of waiting to be noticed.
                guard asksForNote, bookmark.capturedLive, bookmark.note.isEmpty else { return }
                onInteract()
                noteFocused = true
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(.tertiarySystemFill)))
    }

    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(BookmarkCategory.allCases) { category in
                    Button {
                        onInteract()
                        saveNote()
                        onCategory(category)
                    } label: {
                        VStack(spacing: 3) {
                            BookmarkCategoryIcon(category: category, size: 24)
                            Text(category.title)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 112)
                        .frame(minHeight: 72)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .foregroundColor(Color("primaryText"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .scrollIndicators(.visible)
        .simultaneousGesture(DragGesture().onChanged { _ in onInteract() })
    }

    /// Whatever was typed is kept on the way out, however the toast is closed.
    private func finish() {
        saveNote()
        onDismiss()
    }

    private func saveNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != bookmark.note else { return }
        onNote(trimmed)
    }
}


/// The same artwork in the picker, menus and bookmark rows.
///
/// The host portraits are ink on paper: the alpha channel holds the lines and
/// the face is the part that is not there, so the skin is whatever shows
/// through from behind. Tinting that to the label colour is right in light
/// mode and turns the drawing into its own negative in dark - a white beard
/// and a white outline around a face the colour of the background, which
/// reads as a skull rather than as Daško.
///
/// So they keep their own paper, in both appearances. That is not a new idea
/// here: the episode artwork above the player sits on a light square in dark
/// mode for the same reason, and it is the same set of drawings.
///
/// The SF Symbols beside them are drawn as one colour on purpose and go on
/// following the label, which is what they are for.
struct BookmarkCategoryIcon: View {
    let category: BookmarkCategory
    var size: CGFloat = 20

    /// Deliberately not dynamic colours - see the note above. Ink stops just
    /// short of black so it does not out-contrast the text beside it.
    private static let paper = Color(white: 0.93)
    private static let ink = Color(white: 0.12)

    var body: some View {
        Group {
            if let name = category.assetName {
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(BookmarkCategoryIcon.ink)
                    // Room around the drawing so the ears and hair do not run
                    // into the edge of the disc.
                    .padding(size * 0.08)
                    .background(Circle().fill(BookmarkCategoryIcon.paper))
            } else {
                Image(systemName: category.systemImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
