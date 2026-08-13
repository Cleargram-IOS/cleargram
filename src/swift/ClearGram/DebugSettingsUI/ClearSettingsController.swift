import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import UndoUI

// Cleargram settings, laid out like stock Telegram settings: a hub of icon rows, each opening
// a screen of switches grouped into sections with a footer that says what the group does.
//
// The whole tree is data — the `ClearScreen` / `ClearSection` / `ClearToggle` values built in
// `clearRootScreen(context:)` at the bottom of this file. Adding an option is one `ClearToggle`
// line: the entry enum, stable ids, equality and the ItemList plumbing are generic and never
// need to be touched.

// MARK: - Model

private struct ClearToggle {
    enum Storage {
        case config(WritableKeyPath<ClearConfigSettings, Bool>)
        case experimental(WritableKeyPath<ExperimentalUISettings, Bool>)
        // Shown disabled: the switch exists, the behaviour behind it doesn't yet.
        case unimplemented
    }

    let title: String
    let storage: Storage
    // Second line under the title. A closure so it can mirror the current value — the settings
    // signal re-emits on every change, so these read as a live preview of what the option does.
    let subtitle: ((ClearConfigSettings) -> String?)?
    let isEnabled: ((ClearConfigSettings) -> Bool)?
    let requiresRestart: Bool

    init(
        _ title: String,
        _ storage: Storage,
        subtitle: ((ClearConfigSettings) -> String?)? = nil,
        isEnabled: ((ClearConfigSettings) -> Bool)? = nil,
        requiresRestart: Bool = false
    ) {
        self.title = title
        self.storage = storage
        self.subtitle = subtitle
        self.isEnabled = isEnabled
        self.requiresRestart = requiresRestart
    }

    static func soon(_ title: String, _ plan: String) -> ClearToggle {
        return ClearToggle(title, .unimplemented, subtitle: { _ in plan })
    }

    func value(_ settings: ClearConfigSettings, _ experimental: ExperimentalUISettings) -> Bool {
        switch self.storage {
        case let .config(keyPath):
            return settings[keyPath: keyPath]
        case let .experimental(keyPath):
            return experimental[keyPath: keyPath]
        case .unimplemented:
            return false
        }
    }
}

// A row that picks one of a fixed set of Int32 values, shown as a disclosure row with the current
// value as its label and an action sheet with the options.
private struct ClearSelect {
    let title: String
    let keyPath: WritableKeyPath<ClearConfigSettings, Int32>
    // (value, row title). The first entry should be the stock default.
    let options: [(Int32, String)]

    func label(_ settings: ClearConfigSettings) -> String {
        let current = settings[keyPath: self.keyPath]
        return self.options.first(where: { $0.0 == current })?.1 ?? "\(current)"
    }
}

// A plain tappable row that runs code (export / import), rather than storing a value.
private struct ClearAction {
    let title: String
    let perform: (AccountContext, _ present: @escaping (ViewController, Any?) -> Void, _ push: @escaping (ViewController) -> Void) -> Void
}

private enum ClearRow {
    case toggle(ClearToggle)
    case select(ClearSelect)
    case action(ClearAction)
    case screen(ClearScreen)
    case reset(title: String)
}

private final class ClearSection {
    let header: String?
    let footer: ((ClearConfigSettings) -> String?)?
    let rows: [ClearRow]

    init(header: String? = nil, footer: String? = nil, rows: [ClearRow]) {
        self.header = header
        if let footer {
            self.footer = { _ in footer }
        } else {
            self.footer = nil
        }
        self.rows = rows
    }

    init(header: String? = nil, dynamicFooter: @escaping (ClearConfigSettings) -> String?, rows: [ClearRow]) {
        self.header = header
        self.footer = dynamicFooter
        self.rows = rows
    }

    func toggle(at index: Int) -> ClearToggle? {
        guard index < self.rows.count, case let .toggle(toggle) = self.rows[index] else {
            return nil
        }
        return toggle
    }

    func select(at index: Int) -> ClearSelect? {
        guard index < self.rows.count, case let .select(select) = self.rows[index] else {
            return nil
        }
        return select
    }
}

// Reference type: a screen contains rows which contain screens, and a struct can't nest itself.
private final class ClearScreen {
    let title: String
    let icon: UIImage?
    let sections: [ClearSection]

    init(title: String, icon: UIImage? = nil, sections: [ClearSection]) {
        self.title = title
        self.icon = icon
        self.sections = sections
    }
}

// MARK: - Entries

private enum ClearEntry: ItemListNodeEntry {
    case header(section: Int, text: String)
    case toggle(section: Int, index: Int, title: String, subtitle: String?, value: Bool, enabled: Bool)
    case select(section: Int, index: Int, title: String, label: String)
    case action(section: Int, index: Int, title: String)
    case disclosure(section: Int, index: Int, title: String)
    case reset(section: Int, index: Int, title: String)
    case footer(section: Int, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _),
             let .toggle(section, _, _, _, _, _),
             let .select(section, _, _, _),
             let .action(section, _, _),
             let .disclosure(section, _, _),
             let .reset(section, _, _),
             let .footer(section, _):
            return ItemListSectionId(section)
        }
    }

    // Ids must ascend in append order — `ItemListControllerNode` asserts the array is sorted.
    // Header first, then rows, then the footer, with room for ~880 rows per section.
    var stableId: Int {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .toggle(section, index, _, _, _, _):
            return section * 1000 + 10 + index
        case let .select(section, index, _, _):
            return section * 1000 + 10 + index
        case let .action(section, index, _):
            return section * 1000 + 10 + index
        case let .disclosure(section, index, _):
            return section * 1000 + 10 + index
        case let .reset(section, index, _):
            return section * 1000 + 10 + index
        case let .footer(section, _):
            return section * 1000 + 900
        }
    }

    static func < (lhs: ClearEntry, rhs: ClearEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: ClearEntry, rhs: ClearEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(ls, lt), .header(rs, rt)):
            return ls == rs && lt == rt
        case let (.toggle(ls, li, lt, lsub, lv, le), .toggle(rs, ri, rt, rsub, rv, re)):
            return ls == rs && li == ri && lt == rt && lsub == rsub && lv == rv && le == re
        case let (.select(ls, li, lt, ll), .select(rs, ri, rt, rl)):
            return ls == rs && li == ri && lt == rt && ll == rl
        case let (.action(ls, li, lt), .action(rs, ri, rt)):
            return ls == rs && li == ri && lt == rt
        case let (.disclosure(ls, li, lt), .disclosure(rs, ri, rt)):
            return ls == rs && li == ri && lt == rt
        case let (.reset(ls, li, lt), .reset(rs, ri, rt)):
            return ls == rs && li == ri && lt == rt
        case let (.footer(ls, lt), .footer(rs, rt)):
            return ls == rs && lt == rt
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .toggle(section, index, title, subtitle, value, enabled):
            let toggle = args.screen.sections[section].toggle(at: index)
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                text: subtitle,
                value: value,
                enabled: enabled,
                sectionId: self.section,
                style: .blocks,
                updated: { value in
                    if let toggle {
                        args.updateToggle(toggle, value)
                    }
                }
            )
        case let .select(section, index, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.openRow(section, index)
                }
            )
        case let .action(section, index, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.openRow(section, index)
                }
            )
        case let .disclosure(section, index, title):
            var icon: UIImage?
            if case let .screen(screen) = args.screen.sections[section].rows[index] {
                icon = screen.icon
            }
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: icon,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.openRow(section, index)
                }
            )
        case let .reset(_, _, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.reset()
                }
            )
        }
    }
}

private final class ClearArguments {
    let context: AccountContext
    let screen: ClearScreen
    let updateToggle: (ClearToggle, Bool) -> Void
    let openRow: (Int, Int) -> Void
    let reset: () -> Void

    init(
        context: AccountContext,
        screen: ClearScreen,
        updateToggle: @escaping (ClearToggle, Bool) -> Void,
        openRow: @escaping (Int, Int) -> Void,
        reset: @escaping () -> Void
    ) {
        self.context = context
        self.screen = screen
        self.updateToggle = updateToggle
        self.openRow = openRow
        self.reset = reset
    }
}

private func clearEntries(screen: ClearScreen, settings: ClearConfigSettings, experimental: ExperimentalUISettings) -> [ClearEntry] {
    var entries: [ClearEntry] = []
    for (sectionIndex, section) in screen.sections.enumerated() {
        if let header = section.header {
            entries.append(.header(section: sectionIndex, text: header))
        }
        for (rowIndex, row) in section.rows.enumerated() {
            switch row {
            case let .toggle(toggle):
                let enabled: Bool
                if case .unimplemented = toggle.storage {
                    enabled = false
                } else {
                    enabled = toggle.isEnabled?(settings) ?? true
                }
                entries.append(.toggle(
                    section: sectionIndex,
                    index: rowIndex,
                    title: toggle.title,
                    subtitle: toggle.subtitle?(settings),
                    value: toggle.value(settings, experimental),
                    enabled: enabled
                ))
            case let .select(select):
                entries.append(.select(section: sectionIndex, index: rowIndex, title: select.title, label: select.label(settings)))
            case let .action(action):
                entries.append(.action(section: sectionIndex, index: rowIndex, title: action.title))
            case let .screen(child):
                entries.append(.disclosure(section: sectionIndex, index: rowIndex, title: child.title))
            case let .reset(title):
                entries.append(.reset(section: sectionIndex, index: rowIndex, title: title))
            }
        }
        if let footer = section.footer?(settings) {
            entries.append(.footer(section: sectionIndex, text: footer))
        }
    }
    return entries
}

// MARK: - Controller

private func clearScreenController(context: AccountContext, screen: ClearScreen) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?
    var askForRestartImpl: (() -> Void)?

    let accountManager = context.sharedContext.accountManager

    let arguments = ClearArguments(
        context: context,
        screen: screen,
        updateToggle: { toggle, value in
            switch toggle.storage {
            case let .config(keyPath):
                let _ = ClearConfig.update(accountManager: accountManager) { current in
                    var updated = current
                    updated[keyPath: keyPath] = value
                    return updated
                }.start()
            case let .experimental(keyPath):
                let _ = accountManager.transaction { transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings) { entry in
                        var settings = entry?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
                        settings[keyPath: keyPath] = value
                        return EnginePreferencesEntry(settings)
                    }
                }.start()
            case .unimplemented:
                return
            }
            if toggle.requiresRestart {
                askForRestartImpl?()
            }
        },
        openRow: { sectionIndex, rowIndex in
            switch screen.sections[sectionIndex].rows[rowIndex] {
            case let .screen(child):
                pushImpl?(clearScreenController(context: context, screen: child))
            case let .select(select):
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let actionSheet = ActionSheetController(presentationData: presentationData)
                var items: [ActionSheetButtonItem] = []
                for (value, optionTitle) in select.options {
                    items.append(ActionSheetButtonItem(title: optionTitle, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        let _ = ClearConfig.update(accountManager: accountManager) { current in
                            var updated = current
                            updated[keyPath: select.keyPath] = value
                            return updated
                        }.start()
                    }))
                }
                actionSheet.setItemGroups([
                    ActionSheetItemGroup(items: items),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                presentImpl?(actionSheet)
            case let .action(action):
                action.perform(context, { controller, _ in
                    presentImpl?(controller)
                }, { controller in
                    pushImpl?(controller)
                })
            case .toggle, .reset:
                break
            }
        },
        reset: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentImpl?(textAlertController(
                context: context,
                title: "Reset Cleargram Settings",
                text: "Every Cleargram option goes back to its default. Your chats, accounts and Telegram's own settings are not affected.",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Reset", action: {
                        let _ = ClearConfig.reset(accountManager: accountManager).start()
                        askForRestartImpl?()
                    })
                ]
            ))
        }
    )

    let experimentalSignal = accountManager.sharedData(keys: Set([ApplicationSpecificSharedDataKeys.experimentalUISettings]))
    |> map { sharedData -> ExperimentalUISettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        clearConfigEntry(accountManager: accountManager),
        experimentalSignal
    )
    |> map { presentationData, settings, experimental -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let itemListPresentationData = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: itemListPresentationData,
            title: .text(screen.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: itemListPresentationData,
            entries: clearEntries(screen: screen, settings: settings, experimental: experimental),
            style: .blocks,
            animateChanges: true
        )
        return (state, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    pushImpl = { [weak controller] child in
        (controller?.navigationController as? NavigationController)?.pushViewController(child)
    }
    presentImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    askForRestartImpl = { [weak controller] in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "Restart required to apply changes", timeout: nil, customUndoText: "Restart Now"),
            elevatedLayout: false,
            action: { action in
                if action == .undo {
                    exit(0)
                }
                return true
            }
        ), in: .current)
    }

    return controller
}

public func clearSettingsController(context: AccountContext) -> ViewController {
    return clearScreenController(context: context, screen: clearRootScreen())
}

// MARK: - Icons

// Same renderer stock settings rows use — a tinted glyph on a rounded gradient tile.
private enum ClearIcon {
    static let appearance = renderSettingsIcon(name: "Item List/Icons/Brush", backgroundColors: [UIColor(rgb: 0x32ADE6)])
    static let chatList = renderSettingsIcon(name: "Item List/Icons/Folder", backgroundColors: [UIColor(rgb: 0x0079FF)])
    static let tabBar = renderSettingsIcon(name: "Item List/Icons/Topics", backgroundColors: [UIColor(rgb: 0x00C7BE)])
    static let chats = renderSettingsIcon(name: "Item List/Icons/Chat", backgroundColors: [UIColor(rgb: 0x5E5CE6)])
    static let channels = renderSettingsIcon(name: "Item List/Icons/Channel", backgroundColors: [UIColor(rgb: 0xFF9F0A)])
    static let media = renderSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [UIColor(rgb: 0xFF2D55)])
    static let links = renderSettingsIcon(name: "Item List/Icons/Link", backgroundColors: [UIColor(rgb: 0x34C759)])
    static let messageMenu = renderSettingsIcon(name: "Item List/Icons/Hand", backgroundColors: [UIColor(rgb: 0xAF52DE)])
    static let profile = renderSettingsIcon(name: "Item List/Icons/Profile", backgroundColors: [UIColor(rgb: 0xFF453A)])
    static let privacy = renderSettingsIcon(name: "Item List/Icons/Privacy", backgroundColors: [UIColor(rgb: 0x8E8E93)])
    static let debloat = renderSettingsIcon(name: "Item List/Icons/NoAds", backgroundColors: [UIColor(rgb: 0xFFCC02)])
}

// MARK: - The settings tree

private func clearRootScreen() -> ClearScreen {
    return ClearScreen(title: "Cleargram", sections: [
        ClearSection(
            footer: "Every option is off by default — with nothing enabled Cleargram behaves exactly like stock Telegram.",
            rows: [
                .screen(clearAppearanceScreen()),
                .screen(clearChatListScreen()),
                .screen(clearTabBarScreen()),
                .screen(clearChatsScreen()),
                .screen(clearChannelsScreen()),
                .screen(clearMediaScreen()),
                .screen(clearLinksScreen())
            ]
        ),
        ClearSection(
            rows: [
                .screen(clearMessageMenuScreen()),
                .screen(clearProfileScreen()),
                .screen(clearPrivacyScreen()),
                .screen(clearDebloatScreen())
            ]
        ),
        ClearSection(
            header: "BACKUP",
            footer: "Exports every Cleargram option you've changed into a small .cleargram file you can keep or send to someone. Opening one — from Files or from a chat — shows exactly what it would change before anything is applied. Hidden chats, hidden messages and Telegram's own settings are never included.",
            rows: [
                .action(ClearAction(title: "Export Settings", perform: { context, present, push in
                    ClearSettingsTransfer.presentExport(context: context, present: present, push: push, presentNative: { controller in
                        context.sharedContext.mainWindow?.presentNative(controller)
                    })
                })),
                .action(ClearAction(title: "Import Settings", perform: { context, present, push in
                    ClearSettingsTransfer.presentImportPicker(context: context, present: present, presentNative: { controller in
                        context.sharedContext.mainWindow?.presentNative(controller)
                    }, push: push)
                })),
                .toggle(ClearToggle("Import from Chats", .config(\.importSettingsFromChats), subtitle: { _ in "Tap a .cleargram file in a chat to import it" }))
            ]
        ),
        ClearSection(
            footer: "Asks for confirmation first.",
            rows: [
                .reset(title: "Reset All Settings")
            ]
        )
    ])
}

private func clearAppearanceScreen() -> ClearScreen {
    return ClearScreen(title: "Appearance", icon: ClearIcon.appearance, sections: [
        ClearSection(
            header: "GLASS",
            footer: "Two of Telegram's own experimental options, surfaced here. Fake Glass draws the iOS 26 glass look on devices that don't support the real thing; Force Clear Glass drops the tint from glass surfaces so they stay fully transparent.",
            rows: [
                .toggle(ClearToggle("Fake Glass", .experimental(\.fakeGlass))),
                .toggle(ClearToggle("Force Clear Glass", .experimental(\.forceClearGlass)))
            ]
        ),
        ClearSection(
            header: "TEXT",
            footer: "Uses the largest message font (19 pt) in chats, leaving the chat list and Settings at their normal size. Requires a restart.",
            rows: [
                .toggle(ClearToggle("Larger Text in Chats", .config(\.fontSizeOverride), requiresRestart: true))
            ]
        )
    ])
}

private func clearChatListScreen() -> ClearScreen {
    return ClearScreen(title: "Chat List", icon: ClearIcon.chatList, sections: [
        ClearSection(
            header: "ROWS",
            footer: "Compact rows use a smaller avatar and tighter spacing, so more chats fit on screen. Requires a restart.",
            rows: [
                .toggle(ClearToggle("Compact Rows", .config(\.compactChatList), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: "FOLDER TABS",
            footer: "Shrinks the folder tabs above the chat list and lets you drop the “All Chats” tab — swiping right from the first folder still gets you there. Requires a restart.",
            rows: [
                .toggle(ClearToggle("Compact Folder Names", .config(\.compactFolderNames), requiresRestart: true)),
                .toggle(ClearToggle("Hide “All Chats” Tab", .config(\.allChatsHidden), requiresRestart: true)),
                .toggle(ClearToggle.soon("Shorten “All Chats” Title", "Planned: cut the tab title down to a fixed length."))
            ]
        ),
        ClearSection(
            header: "STORIES",
            footer: "Removes stories everywhere: the strip above the chat list, the coloured ring around avatars, the Stories tab in profiles and the story camera buttons. Requires a restart.",
            rows: [
                .toggle(ClearToggle("Hide Stories", .config(\.hideStories), requiresRestart: true)),
                .toggle(ClearToggle("Disable Swipe to Story Camera", .config(\.disableStoryCameraSwipe)))
            ]
        ),
        ClearSection(
            header: "SWIPE",
            rows: [
                .screen(clearSwipeActionsScreen())
            ]
        ),
        ClearSection(
            header: "NOTICES",
            footer: "The banner above the chat list. Promotional notices are Premium offers, gift and profile-photo prompts and whatever link Telegram decides to push there; birthday notices are your contacts' birthdays. New-login reviews, account freeze, password setup and a low Stars balance are always shown — those are the ones you can't afford to miss.",
            rows: [
                .toggle(ClearToggle("Hide Promotional Notices", .config(\.hideChatListPromoNotices))),
                .toggle(ClearToggle("Hide Birthday Notices", .config(\.hideChatListBirthdayNotices)))
            ]
        )
    ])
}

private func clearSwipeActionsScreen() -> ClearScreen {
    return ClearScreen(title: "Swipe Actions", sections: [
        ClearSection(
            header: "SWIPE LEFT",
            footer: "Actions revealed when you drag a chat to the left. A full swipe fires the last one — with Archive on that is Archive, exactly like stock. An action only ever appears where Telegram already offered it; turning one off never moves it somewhere else.",
            rows: [
                .toggle(ClearToggle("Mute", .config(\.swipeActionMute), requiresRestart: true)),
                .toggle(ClearToggle("Delete", .config(\.swipeActionDelete), requiresRestart: true)),
                .toggle(ClearToggle("Archive", .config(\.swipeActionArchive), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: "SWIPE RIGHT",
            footer: "Actions revealed when you drag a chat to the right. A full swipe fires the first one. Turning both off disables that swipe direction entirely.",
            rows: [
                .toggle(ClearToggle("Mark as Read / Unread", .config(\.swipeActionRead), requiresRestart: true)),
                .toggle(ClearToggle("Pin", .config(\.swipeActionPin), requiresRestart: true))
            ]
        )
    ])
}

private func clearTabBarScreen() -> ClearScreen {
    return ClearScreen(title: "Tab Bar", icon: ClearIcon.tabBar, sections: [
        ClearSection(
            header: "TAB BAR",
            dynamicFooter: { settings in
                if settings.hideTabBar {
                    return "The bar at the bottom of the screen is gone; Settings and Contacts stay reachable from the chat list. The options below apply only while the bar is visible. Requires a restart."
                } else {
                    return "Hiding the bar frees the bottom of the screen — Settings and Contacts stay reachable from the chat list. Narrow shrinks the bar when you have fewer than four tabs, so it hugs the icons instead of stretching across the screen. Requires a restart."
                }
            },
            rows: [
                .toggle(ClearToggle("Hide Tab Bar", .config(\.hideTabBar), requiresRestart: true)),
                .toggle(ClearToggle("Show Tab Names", .config(\.showTabNames), isEnabled: { !$0.hideTabBar }, requiresRestart: true)),
                .toggle(ClearToggle("Narrow Tab Bar", .config(\.narrowTabBar), isEnabled: { !$0.hideTabBar }, requiresRestart: true))
            ]
        ),
        ClearSection(
            header: "TABS",
            footer: "Turning the Search tab off removes search from the tab bar entirely — there is no other entry point for it yet. Hiding the Contacts tab requires a restart.",
            rows: [
                .toggle(ClearToggle("Search Tab", .config(\.tabBarSearchEnabled), isEnabled: { !$0.hideTabBar })),
                .toggle(ClearToggle("Hide Contacts Tab", .config(\.disableContactsTab), requiresRestart: true))
            ]
        )
    ])
}

private func clearChatsScreen() -> ClearScreen {
    return ClearScreen(title: "Chats", icon: ClearIcon.chats, sections: [
        ClearSection(
            header: "MESSAGES",
            footer: "Very long messages get a “Show more” button instead of filling the whole screen. Forwarded messages can show when the original was sent, next to who sent it.",
            rows: [
                .toggle(ClearToggle("Collapse Long Messages", .config(\.collapseLongMessages))),
                .toggle(ClearToggle("Original Time on Forwards", .config(\.showForwardedTime)))
            ]
        ),
        ClearSection(
            header: "TIMESTAMPS",
            dynamicFooter: { settings in
                let sample = settings.secondsInMessages ? "12:30:45" : "12:30"
                return "Timestamps under messages look like \(sample). Service messages (“X added Y”) normally carry no time at all."
            },
            rows: [
                .toggle(ClearToggle("Show Seconds", .config(\.secondsInMessages))),
                .toggle(ClearToggle("Time on Service Messages", .config(\.timeOnServiceMessages)))
            ]
        ),
        ClearSection(
            header: "REACTIONS",
            footer: "Removes the paid Star reaction from the reaction bar, and its counter from messages that already have one.",
            rows: [
                .toggle(ClearToggle("Hide Star Reaction", .config(\.hideStarReactionButton))),
                .toggle(ClearToggle("Hide Star Reaction Count", .config(\.hideStarReactionCount)))
            ]
        ),
        ClearSection(
            header: "EDITING & DRAFTS",
            footer: "Double-tap your own message to open the editor, instead of holding it and picking Edit. With cloud drafts off, text you started typing stays on this device and is never uploaded — it won't follow you to another device either.",
            rows: [
                .toggle(ClearToggle("Double-Tap to Edit", .config(\.doubleTapToEdit))),
                .toggle(ClearToggle("Keep Drafts on This Device", .config(\.blockCloudDrafts)))
            ]
        ),
        ClearSection(
            header: "POLLS",
            footer: "Asks before changing a vote you already cast — the retract is easy to trigger by accident and is visible to the poll's author.",
            rows: [
                .toggle(ClearToggle("Confirm Vote Change", .config(\.warnPollsRevote)))
            ]
        ),
        ClearSection(
            header: "BOT KEYBOARDS",
            footer: "Hold a bot keyboard button that opens a link to copy its URL. Login buttons carry a fallback URL that stock Telegram never shows; web-app buttons carry the mini-app URL. Plain link buttons already offer Copy on hold and are left alone.",
            rows: [
                .toggle(ClearToggle("Copy Button URL on Hold", .config(\.copyBotButtonUrl)))
            ]
        ),
        ClearSection(
            header: "EMOJI KEYBOARD",
            footer: "Opens the emoji keyboard on the standard emoji tab instead of recent or custom sets.",
            rows: [
                .toggle(ClearToggle("Standard Emoji First", .config(\.defaultEmojisFirst)))
            ]
        ),
        ClearSection(
            header: "SEARCH",
            rows: [
                .toggle(ClearToggle.soon("Search by User ID", "Planned: find a member's messages by numeric id in groups that hide their member list, where searching by @username fails."))
            ]
        )
    ])
}

private func clearChannelsScreen() -> ClearScreen {
    return ClearScreen(title: "Channels", icon: ClearIcon.channels, sections: [
        ClearSection(
            header: "POSTS",
            footer: "Full-width posts drop the bubble and stretch channel messages across the screen.",
            rows: [
                .toggle(ClearToggle("Full-Width Posts", .config(\.wideChannelPosts)))
            ]
        ),
        ClearSection(
            header: "NAVIGATION",
            footer: "Scrolling past the last post no longer pulls you into the next channel.",
            rows: [
                .toggle(ClearToggle("Disable Scroll to Next Channel", .config(\.disableScrollToNextChannel)))
            ]
        ),
        ClearSection(
            header: "BOTTOM BAR",
            footer: "Removes the bar under a channel's posts — Mute / Unmute once you've joined, Join before that. Selecting messages and in-chat search still get their panels. Joining a channel then needs an invite link or the search result.",
            rows: [
                .toggle(ClearToggle("Hide Bottom Action Bar", .config(\.hideChannelBottomButton)))
            ]
        ),
        ClearSection(
            header: "ADMIN",
            rows: [
                .toggle(ClearToggle.soon("Better Recent Actions", "Planned: show edited messages as a diff in the admin log, instead of truncating the original."))
            ]
        )
    ])
}

private func clearMediaScreen() -> ClearScreen {
    return ClearScreen(title: "Media & Stickers", icon: ClearIcon.media, sections: [
        ClearSection(
            header: "PHOTOS",
            footer: "Adds Copy to the “⋯” menu of the fullscreen viewer. Stock Telegram only copies from the message menu, and only when the message holds a single photo without a caption.",
            rows: [
                .toggle(ClearToggle("Copy Image in Gallery", .config(\.copyImageInGallery)))
            ]
        ),
        ClearSection(
            header: "CAMERA",
            dynamicFooter: { settings in
                if settings.disableGalleryCamera {
                    return "The camera tile is gone from the attachment picker; the grid starts with your photos. Also lets you pick the front or back camera before recording a video message."
                } else if settings.compactGalleryCamera {
                    return "The camera tile in the attachment picker is one square cell with a plain icon instead of two cells of live preview — no capture session runs while you browse, so no battery drain and no camera-in-use indicator. Tapping it still opens the camera. Also lets you pick the front or back camera before recording a video message."
                } else {
                    return "The attachment picker normally runs a live camera preview two cells tall. Hide it entirely, or shrink it to a single cell with a static icon and no capture session. Also lets you pick the front or back camera before recording a video message."
                }
            },
            rows: [
                .toggle(ClearToggle("Hide Camera in Picker", .config(\.disableGalleryCamera))),
                .toggle(ClearToggle("Compact Camera Tile", .config(\.compactGalleryCamera), isEnabled: { !$0.disableGalleryCamera })),
                .toggle(ClearToggle("Camera for Video Messages", .config(\.videoMessageCameraSelection)))
            ]
        ),
        ClearSection(
            header: "VIDEO",
            footer: "“Send as Video Message” appears in the ⋯ menu of the media picker when a single video is selected. The video is cropped to a centred square, re-encoded to 400×400 h.264 and trimmed to the first 60 seconds — the same conversion the round-video camera uses.",
            rows: [
                .toggle(ClearToggle("Send Video as Video Message", .config(\.sendVideoAsCircle))),
                .toggle(ClearToggle.soon("Audio Source for Video Messages", "Planned: record a video message through a Bluetooth or external mic instead of the built-in one.")),
                .toggle(ClearToggle.soon("Original Video Quality", "Planned: send a video as-is, skipping re-encoding."))
            ]
        ),
        ClearSection(
            header: "AUDIO",
            dynamicFooter: { settings in
                if settings.showAudioFormatBitrate {
                    return "The music player subtitle reads like “Artist · ALAC 24-bit/96 kHz · 2304 kbps”."
                } else {
                    return "Shows the codec and bitrate of a track next to the artist in the music player. ALAC is told apart from AAC by reading the container once the file has finished downloading — while it is still streaming, anything above 500 kbps is taken as lossless."
                }
            },
            rows: [
                .toggle(ClearToggle("Show Codec & Bitrate", .config(\.showAudioFormatBitrate)))
            ]
        ),
        ClearSection(
            header: "TRANSFERS",
            footer: "Downloads and uploads in larger chunks (1 MB down, 512 KB up instead of 512/256 KB). Faster on a stable connection; on a flaky one a failed chunk costs more to retry.",
            rows: [
                .toggle(ClearToggle("Faster File Transfer", .config(\.fasterFileLoad)))
            ]
        ),
        ClearSection(
            header: "STICKERS",
            footer: "Save to Photos appears in the context menu of static stickers. Square Sticker Corners drops the 12.5% rounding from the sticker editor's frame, from a photo you insert into it and from the exported file — a cut-out subject has no corners to square, so it looks the same either way. Show Pack Owner adds an entry to a sticker pack's “⋯” menu that opens the profile of whoever uploaded it.",
            rows: [
                .toggle(ClearToggle("Save Sticker to Photos", .config(\.saveStickerToPhotos))),
                .toggle(ClearToggle("Square Sticker Corners", .config(\.flatStickerCorners))),
                .toggle(ClearToggle("Show Pack Owner", .config(\.showPackOwner)))
            ]
        ),
        ClearSection(
            header: "RECENT STICKERS",
            footer: "Telegram keeps the last 20 stickers you used, and the cloud copy gets trimmed back to that on every sync. Cleargram keeps the ones the server drops, so the Recent row can grow past it. The list fills up as you use stickers — nothing is restored retroactively, the extras live on this device only, and clearing recent stickers still clears everything.",
            rows: [
                .select(ClearSelect(
                    title: "Keep",
                    keyPath: \.recentStickersLimit,
                    options: [(0, "Default (20)"), (30, "30"), (50, "50"), (100, "100"), (200, "200")]
                ))
            ]
        )
    ])
}

private func clearLinksScreen() -> ClearScreen {
    return ClearScreen(title: "Links", icon: ClearIcon.links, sections: [
        ClearSection(
            header: "TRACKING",
            dynamicFooter: { settings in
                if settings.stripTrackingParams {
                    return "example.com/article?utm_source=telegram&fbclid=… becomes example.com/article.\n\nApplies to the link preview while you compose, and to Copy on a link. The text you actually send is left as you typed it."
                } else {
                    return "Removes utm_*, fbclid, igshid, ref and similar parameters from links.\n\nApplies to the link preview while you compose, and to Copy on a link. The text you actually send is left as you typed it."
                }
            },
            rows: [
                .toggle(ClearToggle("Strip Tracking Parameters", .config(\.stripTrackingParams)))
            ]
        ),
        ClearSection(
            header: "PREVIEWS",
            footer: "Some sites block Telegram from building a preview. This swaps the host for a mirror that doesn't: x/twitter → fixupx, instagram → kkclip, tiktok → kktiktok, reddit → rxddit, bsky → fxbsky, pixiv → phixiv.",
            rows: [
                .toggle(ClearToggle("Rewrite Links for Previews", .config(\.replacePreviewLinks)))
            ]
        ),
        ClearSection(
            header: "TELEGRAM LINKS",
            footer: "Asks before opening a t.me or tg:// link — those can join a channel or open a bot with one tap.",
            rows: [
                .toggle(ClearToggle("Confirm Telegram Links", .config(\.confirmInternalLinks)))
            ]
        )
    ])
}

private func clearMessageMenuScreen() -> ClearScreen {
    return ClearScreen(title: "Message Menu", icon: ClearIcon.messageMenu, sections: [
        ClearSection(
            header: "HIDE ACTIONS",
            footer: "Removes entries from the menu that appears when you hold a message. What you hide here stays reachable elsewhere — swipe still replies, and selection still starts from the chat's own menu.",
            rows: [
                .toggle(ClearToggle("Reply", .config(\.hideContextMenuReply))),
                .toggle(ClearToggle("Pin", .config(\.hideContextMenuPin))),
                .toggle(ClearToggle("Forward", .config(\.hideContextMenuForward))),
                .toggle(ClearToggle("Report", .config(\.hideContextMenuReport))),
                .toggle(ClearToggle("Select", .config(\.hideContextMenuSelect)))
            ]
        )
    ])
}

private func clearProfileScreen() -> ClearScreen {
    return ClearScreen(title: "Profile", icon: ClearIcon.profile, sections: [
        ClearSection(
            header: "PROFILES",
            footer: "Adds the numeric id and the datacenter under the profile header — for users, bots, groups, supergroups and channels alike. Tap the row to copy it; hold a group or channel id to copy the bot-API form (-100…) instead. The datacenter roughly tells you which region the account was registered in.",
            rows: [
                .toggle(ClearToggle("Show ID", .config(\.showProfileId))),
                .toggle(ClearToggle("Show Datacenter", .config(\.showDC)))
            ]
        ),
        ClearSection(
            header: "ACCOUNT ORIGIN",
            footer: "Registration month and the country the account's phone number belongs to. Telegram sends this only with the first message from someone who isn't your contact, so it's available when the client cached it back then — for everyone else the rows simply don't appear. Month precision; there is no exact date in the API.",
            rows: [
                .toggle(ClearToggle("Show Registration Date", .config(\.showRegistrationDate))),
                .toggle(ClearToggle("Show Phone Country", .config(\.showPhoneCountry)))
            ]
        ),
        ClearSection(
            header: "YOUR PROFILE",
            footer: "Hides your phone number in Settings, so it isn't exposed when someone glances at your screen. It stays visible to whoever you already share it with. Requires a restart.",
            rows: [
                .toggle(ClearToggle("Hide My Phone Number", .config(\.hidePhoneInSettings), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: "ACTIONS",
            footer: "Removes the call button from profiles, so you can't ring someone by mistake.",
            rows: [
                .toggle(ClearToggle("Hide Call Button", .config(\.disableCallsButton)))
            ]
        )
    ])
}

private func clearPrivacyScreen() -> ClearScreen {
    return ClearScreen(title: "Privacy", icon: ClearIcon.privacy, sections: [
        ClearSection(
            header: "CONFIRMATIONS",
            footer: "Asks before placing a call, so a misplaced tap doesn't ring someone.",
            rows: [
                .toggle(ClearToggle("Confirm Calls", .config(\.confirmCalls)))
            ]
        ),
        ClearSection(
            header: "FACE ID / TOUCH ID",
            footer: "These actions run only after a successful check. If biometry is unavailable — locked out, denied or not enrolled — the device passcode is asked for instead; on a device with no passcode at all the action is blocked.",
            rows: [
                .toggle(ClearToggle("Confirm Delete Chat", .config(\.biometricConfirmDeleteChat))),
                .toggle(ClearToggle("Confirm Clear History", .config(\.biometricConfirmClearHistory))),
                .toggle(ClearToggle("Confirm Log Out", .config(\.biometricConfirmLogout)))
            ]
        ),
        ClearSection(
            header: "PARANOIA",
            rows: [
                .toggle(ClearToggle.soon("Paranoia Mode", "Planned: keep hidden chats out of contacts, recent calls, search and the share sheet too — not just the chat list."))
            ]
        )
    ])
}

private func clearDebloatScreen() -> ClearScreen {
    return ClearScreen(title: "Debloat", icon: ClearIcon.debloat, sections: [
        ClearSection(
            header: "ADS & PROMOTION",
            footer: "Sponsored posts are injected by Telegram into public channels; the similar-channels block appears right after you join one.",
            rows: [
                .toggle(ClearToggle("Hide Sponsored Messages", .config(\.hideSponsoredMessages))),
                .toggle(ClearToggle("Hide Similar Channels", .config(\.hideSimilarChannels)))
            ]
        ),
        ClearSection(
            header: "AI",
            footer: "Removes the summarize button on messages, the AI compose buttons in the input panels and the AI entry in the attachment menu.",
            rows: [
                .toggle(ClearToggle("Hide AI Features", .config(\.hideAiFeatures)))
            ]
        ),
        ClearSection(
            header: "MONETIZATION",
            rows: [
                .toggle(ClearToggle.soon("Hide Premium, Stars & Gifts", "Planned: strip the Premium upsell, Stars balance, gifts, boosts and collectibles out of the interface."))
            ]
        ),
        ClearSection(
            header: "ADMIN",
            footer: "Hides the “N people want to join” banner admins see at the top of a channel. The requests themselves are untouched.",
            rows: [
                .toggle(ClearToggle("Hide Join Requests Banner", .config(\.hideChannelJoinRequests)))
            ]
        )
    ])
}
