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
                BookmarkRowView(bookmark: bookmark,
                                category: viewModel.category(of: bookmark),
                                canPlay: viewModel.canOpen(bookmark))
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
                viewModel.activeCategoryId = nil
            } label: {
                Label("Sve", systemImage: viewModel.activeCategoryId == nil ? "checkmark" : "")
            }
            ForEach(viewModel.availableCategories) { category in
                Button {
                    // Pressing the one that is on takes it off, the same way
                    // the category menu on a row works. "Sve" stays, because
                    // it is the only way out when you cannot remember which
                    // one you picked.
                    viewModel.activeCategoryId =
                        viewModel.activeCategoryId == category.id ? nil : category.id
                } label: {
                    Label {
                        Text(category.title)
                    } icon: {
                        if viewModel.activeCategoryId == category.id {
                            Image(systemName: "checkmark")
                        } else {
                            BookmarkCategoryIcon(category, size: BookmarkCategoryIcon.inMenu)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.activeCategoryId == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    @ViewBuilder
    private func categoryOptions(for bookmark: Bookmark) -> some View {
        ForEach(viewModel.allCategories) { category in
            Button {
                // Choosing the one it already has clears it, so the menu is
                // both how you set a category and how you take it back.
                viewModel.setCategory(bookmark.categoryId == category.id ? nil : category.id,
                                      for: bookmark)
            } label: {
                Label {
                    Text(category.title)
                } icon: {
                    if bookmark.categoryId == category.id {
                        Image(systemName: "checkmark")
                    } else {
                        BookmarkCategoryIcon(category, size: BookmarkCategoryIcon.inMenu)
                    }
                }
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
    /// Looked up once by the view model rather than resolved here: a row is
    /// drawn again on every tick of the player.
    var category: BookmarkCategoryItem?
    /// Whether the episode behind it is on this device. See
    /// BookmarksViewModel.canOpen.
    var canPlay: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon
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

            // On the trailing edge rather than in the badge. The badge says
            // what a tap does - play something, or nothing yet - and the
            // category is a different fact about the row; putting them in one
            // place meant every bookmark you could actually play showed no
            // category at all.
            if let category {
                BookmarkCategoryIcon(category, size: 22)
                    .help(Text(category.title))
                    .accessibilityLabel(Text(category.title))
            }

            if !canPlay {
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

    /// A triangle where a tap plays something, a bookmark where it does not.
    /// Only that: the category moved to the trailing edge, where it shows on
    /// every row rather than only on the ones with nothing to play.
    @ViewBuilder
    private var leadingIcon: some View {
        Image(systemName: canPlay ? "play.fill" : "bookmark")
    }

    /// One that has not found its episode is a note and nothing more: tapping
    /// it plays nothing. It used to be dimmed as a whole, which read as
    /// disabled - as if the row were broken rather than waiting. A colour of
    /// its own says the same thing without taking the text away, and the
    /// category symbol gives way to the broadcast one so the reason is legible
    /// at a glance.
    private var leadingColor: Color {
        canPlay ? Color("primaryLink") : Color("noteAccent")
    }

    private var badgeFill: Color {
        canPlay
            ? Color(.tertiarySystemFill)
            : Color("noteAccent").opacity(0.14)
    }
}
