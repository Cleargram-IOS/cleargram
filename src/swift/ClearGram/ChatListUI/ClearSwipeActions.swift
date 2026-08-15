import Foundation
import ItemListUI
import TelegramUIPreferences

// Chat-list swipe actions. Stock builds two arrays of `ItemListRevealOption` in
// `ChatListItem.asyncLayout` — one per swipe direction — and this rearranges them at a single
// point, after stock has decided what this particular row is even allowed to offer.
//
// Nothing is ever *added*: the pool is exactly what stock produced for this row, so an action can
// never appear where it wouldn't work. Only the subset, the order and the side are ours.
public enum ClearSwipeAction: String, CaseIterable {
    case pin
    case mute
    case read
    case delete
    case archive

    // Not shown anywhere today — the reveal options keep the titles stock gave them, already
    // localized by Telegram. Kept for debugging, and localized so it stays usable if it ever
    // reaches the screen.
    public var title: String {
        switch self {
        case .pin: return ClearStrings.tr("Pin", "Закрепить")
        case .mute: return ClearStrings.tr("Mute", "Без звука")
        case .read: return ClearStrings.tr("Read / Unread", "Прочитано / Не прочитано")
        case .delete: return ClearStrings.tr("Delete", "Удалить")
        case .archive: return ClearStrings.tr("Archive", "Архивировать")
        }
    }
}

public enum ClearSwipeActions {
    // Cheap early-out: true only when the user actually changed something.
    public static var isConfigured: Bool {
        let c = ClearConfig.current()
        if !c.swipeActionsLeft.isEmpty || !c.swipeActionsRight.isEmpty {
            return true
        }
        return !(c.swipeActionPin && c.swipeActionMute && c.swipeActionRead && c.swipeActionDelete && c.swipeActionArchive)
    }

    private static func isAllowed(_ action: ClearSwipeAction, _ c: ClearConfigSettings) -> Bool {
        switch action {
        case .pin: return c.swipeActionPin
        case .mute: return c.swipeActionMute
        case .read: return c.swipeActionRead
        case .delete: return c.swipeActionDelete
        case .archive: return c.swipeActionArchive
        }
    }

    /// `family` maps a stock RevealOptionKey raw value to a configurable action. Keys absent from
    /// the map (ungroup, edit, hidePsa, hide/unhide, open/close) are never dropped and never moved
    /// — they stay on the side stock put them on.
    public static func arrange(
        left: [ItemListRevealOption],
        right: [ItemListRevealOption],
        family: [Int32: ClearSwipeAction]
    ) -> (left: [ItemListRevealOption], right: [ItemListRevealOption]) {
        let c = ClearConfig.current()
        let order: (left: [ClearSwipeAction], right: [ClearSwipeAction]) = (
            c.swipeActionsLeft.compactMap(ClearSwipeAction.init(rawValue:)),
            c.swipeActionsRight.compactMap(ClearSwipeAction.init(rawValue:))
        )

        // No explicit order — keep stock's sides and order, just drop the excluded actions.
        if order.left.isEmpty && order.right.isEmpty {
            let keep: (ItemListRevealOption) -> Bool = { option in
                guard let action = family[option.key] else {
                    return true
                }
                return isAllowed(action, c)
            }
            return (left.filter(keep), right.filter(keep))
        }

        // Explicit order wins; the pool is still only what stock offered for THIS row.
        var pool: [(ClearSwipeAction, ItemListRevealOption)] = []
        var unmanagedLeft: [ItemListRevealOption] = []
        var unmanagedRight: [ItemListRevealOption] = []
        for option in left {
            if let action = family[option.key] {
                pool.append((action, option))
            } else {
                unmanagedLeft.append(option)
            }
        }
        for option in right {
            if let action = family[option.key] {
                pool.append((action, option))
            } else {
                unmanagedRight.append(option)
            }
        }
        func take(_ actions: [ClearSwipeAction]) -> [ItemListRevealOption] {
            var result: [ItemListRevealOption] = []
            for action in actions {
                if let index = pool.firstIndex(where: { $0.0 == action }) {
                    result.append(pool[index].1)
                    pool.remove(at: index)
                }
            }
            return result
        }
        // Order of these two calls decides who wins when an action is listed on both sides.
        let newLeft = take(order.left)
        let newRight = take(order.right)
        // The full-swipe slot is index 0 on the left and the last index on the right — keep it for
        // the user's choice and park the unmanaged options on the inside.
        return (newLeft + unmanagedLeft, unmanagedRight + newRight)
    }
}
