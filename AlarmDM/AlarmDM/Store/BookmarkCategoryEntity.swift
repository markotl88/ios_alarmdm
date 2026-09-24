//
//  BookmarkCategoryEntity.swift
//  AlarmDM
//
//  A category as the person has arranged it: the ones the app ships with, the
//  ones they made, and the order they want them in. This is the half that
//  syncs.
//

import Foundation
import SwiftData

/// One row per category, built-in or not.
///
/// Built-in categories exist in code as `BookmarkCategory`; a row for one
/// carries only what the person changed about it, which today is where it
/// sits in the list. Its name stays in code so it goes on being translated -
/// a row that copied "Muzika" would show Serbian to somebody reading the app
/// in English.
///
/// A category they made has nowhere else to live, so the row is all of it.
///
/// Not `@Attribute(.unique)` on `id`, because CloudKit refuses unique
/// constraints - see PodcastEntity. Two devices seeding the built-ins before
/// either has heard of the other each write a full set, and both sets end up
/// everywhere. The seed is deterministic so the duplicates are identical, and
/// BookmarkCatalog folds them on read the way EpisodeStateEntity.effective
/// does for listening.
@Model
final class BookmarkCategoryEntity {

    /// A built-in's raw value, or a UUID string for one the person made.
    /// This is what a bookmark stores, so it must never change under a
    /// category that bookmarks already point at.
    var id: String = ""

    /// Empty for a built-in: its title is localized in code. What the person
    /// typed, for one they made - never translated, because it is theirs.
    var name: String = ""

    /// The artwork, for a category they made: one of the three head assets.
    /// Nil for a built-in, which gets its icon from the enum.
    var iconName: String?

    /// Where it sits. Seeded from the declaration order so two devices arrive
    /// at the same numbers without talking, and rewritten when the list is
    /// rearranged.
    var sortOrder: Int = 0

    /// Whether the app ships this one. A built-in cannot be deleted; renaming
    /// and moving are the person's to do.
    var isBuiltIn: Bool = false

    /// When this row was last changed, and the tiebreaker when two devices
    /// rearranged the list separately. Same rule as a listening position: the
    /// later moment is the true one, because CloudKit keeps whichever write
    /// landed last and that is not the same thing.
    var editedAt: Date?

    init(id: String,
         name: String = "",
         iconName: String? = nil,
         sortOrder: Int,
         isBuiltIn: Bool,
         editedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
        self.editedAt = editedAt
    }

    /// Which of two rows for the same category was arranged last. A row
    /// nobody has touched has no date and loses to one that has.
    static func isNewer(_ lhs: BookmarkCategoryEntity, than rhs: BookmarkCategoryEntity) -> Bool {
        (lhs.editedAt ?? .distantPast) > (rhs.editedAt ?? .distantPast)
    }
}
