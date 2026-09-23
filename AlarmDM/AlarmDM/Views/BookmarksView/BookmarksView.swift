//
//  BookmarksView.swift
//  AlarmDM
//
//  Everything caught with the bookmark button. Tapping one opens the episode
//  at the second it points to.
//

import SwiftUI

struct BookmarksView: View {

    @StateObject private var viewModel = BookmarksViewModel()
    @EnvironmentObject private var playerViewModel: PlayerViewModel

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Zabeleženo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.availableCategories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { categoryMenu }
            }
        }
        .onAppear {
            viewModel.reload()
            Analytics.record(.bookmarksOpened)
            Analytics.recordBookmarksHeld(viewModel.bookmarks.count)
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.visibleBookmarks) { bookmark in
                BookmarkRowView(bookmark: bookmark)
                    .contentShape(Rectangle())
                    .onTapGesture { open(bookmark) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            viewModel.delete(bookmark)
                        } label: {
                            Label("Obriši", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .contextMenu { categoryOptions(for: bookmark) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.visibleBookmarks.isEmpty {
                Text("Nema zabeleški u ovoj kategoriji.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                viewModel.activeCategory = nil
            } label: {
                Label("Sve", systemImage: viewModel.activeCategory == nil ? "checkmark" : "")
            }
            ForEach(viewModel.availableCategories) { category in
                Button {
                    viewModel.activeCategory = category
                } label: {
                    Label(category.title,
                          systemImage: viewModel.activeCategory == category ? "checkmark" : category.systemImage)
                }
            }
        } label: {
            Image(systemName: viewModel.activeCategory == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    @ViewBuilder
    private func categoryOptions(for bookmark: Bookmark) -> some View {
        ForEach(BookmarkCategory.allCases) { category in
            Button {
                // Choosing the one it already has clears it, so the menu is
                // both how you set a category and how you take it back.
                viewModel.setCategory(bookmark.category == category ? nil : category, for: bookmark)
            } label: {
                Label(category.title,
                      systemImage: bookmark.category == category ? "checkmark" : category.systemImage)
            }
        }
    }

    private func open(_ bookmark: Bookmark) {
        guard let episode = viewModel.episode(for: bookmark) else { return }
        Analytics.record(.bookmarkPlayed, ["kind": bookmark.capturedLive ? "live" : "episode"])
        playerViewModel.play(episode, startingAt: bookmark.position)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Još nema zabeleški.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Dok slušaš, dodirni dugme za zabelešku u plejeru. Zabeleška se čuva pet sekundi pre trenutne pozicije.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct BookmarkRowView: View {

    let bookmark: Bookmark

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: leadingSymbol)
                .font(.footnote)
                .foregroundColor(leadingColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(badgeFill))

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color("primaryText"))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(bookmark.positionText)
                        .monospacedDigit()
                    if let subtitle = bookmark.displaySubtitle {
                        Text(verbatim: "·")
                        Text(subtitle).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundColor(Color("secondaryText"))
            }

            Spacer(minLength: 0)

            if bookmark.isAwaitingEpisode {
                // "UŽIVO" said where it came from, next to a broadcast symbol,
                // which together read as something to press. It came from the
                // radio, which the subtitle already says; what this has to say
                // is that there is nothing behind it yet.
                HStack(spacing: 4) {
                    Text("BELEŠKA")
                        .font(.caption2.weight(.bold))
                }
                .foregroundColor(Color("noteAccent"))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color("noteAccent").opacity(0.14)))
            }
        }
        .padding(.vertical, 4)
    }

    /// A triangle where a tap plays something, and the category's own symbol
    /// where it does not — a note for a song, a bookmark for anything else.
    /// Every row used to carry a symbol that said nothing about which of the
    /// two it was.
    private var leadingSymbol: String {
        if !bookmark.isAwaitingEpisode { return "play.fill" }
        if let category = bookmark.category { return category.systemImage }
        return "bookmark"
    }

    /// One that has not found its episode is a note and nothing more: tapping
    /// it plays nothing. It used to be dimmed as a whole, which read as
    /// disabled — as if the row were broken rather than waiting. A colour of
    /// its own says the same thing without taking the text away, and the
    /// category symbol gives way to the broadcast one so the reason is legible
    /// at a glance.
    private var leadingColor: Color {
        bookmark.isAwaitingEpisode ? Color("noteAccent") : Color("primaryLink")
    }

    private var badgeFill: Color {
        bookmark.isAwaitingEpisode
            ? Color("noteAccent").opacity(0.14)
            : Color(.tertiarySystemFill)
    }
}
