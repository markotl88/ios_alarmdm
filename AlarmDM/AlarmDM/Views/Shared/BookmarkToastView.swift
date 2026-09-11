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
    let onCategory: (BookmarkCategory) -> Void
    let onNote: (String) -> Void
    /// Called the moment the toast is touched, so whoever put it on screen
    /// stops counting down. Typing a note takes longer than five seconds.
    let onInteract: () -> Void
    let onDismiss: () -> Void

    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(bookmark: Bookmark,
         onCategory: @escaping (BookmarkCategory) -> Void,
         onNote: @escaping (String) -> Void,
         onInteract: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.bookmark = bookmark
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

            // Live radio gets no categories: what was caught is a moment on
            // air, and sorting it can wait for the list.
            if !bookmark.isLive {
                categories
            }
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
                // own — no position in an episode, no song title. Whatever gets
                // typed here is the only thing that row will ever say, so the
                // field asks for it instead of waiting to be noticed.
                guard bookmark.isLive, bookmark.note.isEmpty else { return }
                onInteract()
                noteFocused = true
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(.tertiarySystemFill)))
    }

    private var categories: some View {
        HStack(spacing: 6) {
            ForEach(BookmarkCategory.allCases) { category in
                Button {
                    onInteract()
                    saveNote()
                    onCategory(category)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: category.systemImage)
                            .font(.footnote)
                        Text(category.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
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
