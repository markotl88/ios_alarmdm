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
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .font(.footnote)
                    .foregroundColor(Color("primaryLink"))

                Text("Zabeleženo na \(bookmark.positionText)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color("primaryText"))

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color("secondaryText"))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zatvori")
            }

            // Live radio gets no categories: what was caught is a moment on
            // air, and sorting it can wait for the list.
            if !bookmark.isLive {
                HStack(spacing: 6) {
                    ForEach(BookmarkCategory.allCases) { category in
                        Button {
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
}
