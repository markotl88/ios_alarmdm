//
//  BookmarkCatalog.swift
//  AlarmDM
//
//  The list of categories as the person sees it: what the app ships, what
//  they made, in the order they arranged. One place, so the picker in the
//  toast, the filter in the list and a bookmark's own row cannot disagree.
//

import Foundation
import SwiftData

/// A category ready to draw, whichever kind it is.
///
/// A value rather than a row: every screen that shows the list holds it while
/// it draws, and reading the store while drawing is what chapter and verse of
/// this codebase has already been bitten by.
struct BookmarkCategoryItem: Identifiable, Equatable {

    /// What a bookmark stores. A built-in's raw value, or a UUID string.
    let id: String
    /// Set when the app ships this one; nil for a category they made.
    let builtIn: BookmarkCategory?
    let customName: String
    let customIcon: String?
    let sortOrder: Int

    var isBuiltIn: Bool { builtIn != nil }

    /// A built-in on its own, for the places that still hold the enum.
    init(_ builtIn: BookmarkCategory) {
        self.init(id: builtIn.rawValue,
                  builtIn: builtIn,
                  customName: "",
                  customIcon: nil,
                  sortOrder: BookmarkCatalog.defaultOrder(of: builtIn))
    }

    init(id: String, builtIn: BookmarkCategory?, customName: String,
         customIcon: String?, sortOrder: Int) {
        self.id = id
        self.builtIn = builtIn
        self.customName = customName
        self.customIcon = customIcon
        self.sortOrder = sortOrder
    }

    /// The built-in's title comes from code so it is still translated; theirs
    /// is what they typed and is never translated.
    var title: String { builtIn?.title ?? customName }

    var assetName: String? { builtIn?.assetName ?? customIcon }

    /// Only reached when there is no artwork. A category they made always has
    /// artwork - it is chosen when the category is - so this is the built-ins.
    var systemImage: String { builtIn?.systemImage ?? "bookmark" }
}

enum BookmarkCatalog {

    /// The three drawings a category of their own can wear. Deliberately a
    /// short list: the point is to tell one of their categories from another
    /// at a glance, not to build an icon set.
    /// Both of them first, and so the default: a category of their own is
    /// theirs rather than one host's, and picking a single face for it says
    /// something the name probably did not mean.
    static let customIcons = ["bookmark-dasko-mladja", "bookmark-dasko", "bookmark-mladja"]

    /// What each of the three drawings is called out loud.
    ///
    /// The pickers show the artwork and nothing else, and the artwork is
    /// hidden from accessibility - it is decoration for anybody who can see
    /// the label beside it. In the icon picker there is no label beside it,
    /// so without this a VoiceOver user is offered three buttons that are all
    /// called "Button" and told which one is selected.
    ///
    /// Names, so not translated.
    static func name(ofCustomIcon icon: String) -> String {
        switch icon {
        case "bookmark-dasko": return "Daško"
        case "bookmark-mladja": return "Mlađa"
        default: return "Daško i Mlađa"
        }
    }

    /// How far apart the built-ins are seeded, so one can be dropped between
    /// two of them without renumbering the list.
    static let step = 100

    /// Where a built-in sits before anybody has moved it. Deterministic, so
    /// two devices seeding before they have heard of each other write the
    /// same numbers and the duplicate rows are identical.
    static func defaultOrder(of category: BookmarkCategory) -> Int {
        (BookmarkCategory.allCases.firstIndex(of: category) ?? 0) * step
    }

    /// The list to draw, folded and ordered.
    ///
    /// Duplicates are folded here and left where they are; deleting them
    /// belongs to the next write, for the same reason reading an episode does
    /// not tidy its rows - see PodcastRepository.podcast(with:).
    ///
    /// A built-in with no row at all still appears, at the place the app
    /// ships it in. That is what lets a later version add a category without
    /// migrating anybody: it simply turns up.
    static func arranged(_ rows: [BookmarkCategoryEntity]) -> [BookmarkCategoryItem] {
        var newest: [String: BookmarkCategoryEntity] = [:]
        for row in rows {
            guard let held = newest[row.id] else { newest[row.id] = row; continue }
            // The later arrangement wins. Equal dates fall back to the lower
            // position, so two devices that never touched the list still
            // agree on which identical row they are looking at.
            if BookmarkCategoryEntity.isNewer(row, than: held) { newest[row.id] = row }
            else if !BookmarkCategoryEntity.isNewer(held, than: row), row.sortOrder < held.sortOrder {
                newest[row.id] = row
            }
        }

        var items: [BookmarkCategoryItem] = BookmarkCategory.allCases.map { category in
            let row = newest[category.rawValue]
            return BookmarkCategoryItem(
                id: category.rawValue,
                builtIn: category,
                customName: "",
                customIcon: nil,
                sortOrder: row?.sortOrder ?? defaultOrder(of: category)
            )
        }

        items += newest.values
            .filter { !$0.isBuiltIn && BookmarkCategory(rawValue: $0.id) == nil }
            .map {
                BookmarkCategoryItem(id: $0.id,
                                     builtIn: nil,
                                     customName: $0.name,
                                     customIcon: $0.iconName,
                                     sortOrder: $0.sortOrder)
            }

        // By id after position, so a list that has never been arranged is in
        // the same order on every device rather than in whatever order the
        // store handed the rows back.
        return items.sorted {
            $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
        }
    }

    /// Where a new category goes: after everything, far enough that the next
    /// one has room too.
    static func orderAfter(_ items: [BookmarkCategoryItem]) -> Int {
        (items.map(\.sortOrder).max() ?? 0) + step
    }

    /// The positions to write after a drag, as ids in their new order. Every
    /// row gets a number, including built-ins that never had one - once the
    /// list has been arranged by hand, the shipped order stops being the
    /// answer.
    static func positions(forNewOrder ids: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0 * step) })
    }
}
