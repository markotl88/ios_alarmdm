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
        .onAppear { viewModel.reload() }
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
            Text("Dok slušaš, pritisni dugme sa oznakom na plejeru — zabeleži se trenutak pet sekundi unazad.")
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
            // A live capture that has not found its episode is a note and
            // nothing more — no audio behind it, nowhere to jump. The broadcast
            // glyph says that before the tap does.
            Image(systemName: leadingSymbol)
                .font(.footnote)
                .foregroundColor(leadingColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(.tertiarySystemFill)))

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color("primaryText"))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(bookmark.positionText)
                        .monospacedDigit()
                    if let subtitle = bookmark.displaySubtitle {
                        Text("·")
                        Text(subtitle).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundColor(Color("secondaryText"))
            }

            Spacer(minLength: 0)

            if bookmark.isAwaitingEpisode {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("UŽIVO")
                        .font(.caption2.weight(.bold))
                }
                .foregroundColor(Color("secondaryText"))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
        }
        .padding(.vertical, 4)
        // Dimmed as a whole, because none of it leads anywhere yet.
        .opacity(bookmark.isAwaitingEpisode ? 0.75 : 1)
    }

    private var leadingSymbol: String {
        if let category = bookmark.category { return category.systemImage }
        return bookmark.isAwaitingEpisode ? "dot.radiowaves.left.and.right" : "bookmark"
    }

    private var leadingColor: Color {
        guard bookmark.category != nil else { return .secondary }
        return Color("primaryLink")
    }
}
