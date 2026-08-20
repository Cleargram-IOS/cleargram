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

// Shorthand for `ClearStrings.tr` — English source text first, Russian second. Kept short on
// purpose: the tree below reads as a table of rows, and a longer call would bury the titles.
private func L(_ en: String, _ ru: String) -> String {
    return ClearStrings.tr(en, ru)
}

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
//
// With a `label` it renders as a disclosure row showing that text on the right instead — for
// rows that open a screen and should say what is currently picked there. The closure is given
// the settings so the label re-reads on every change, like a toggle's subtitle.
private struct ClearAction {
    let title: String
    let label: ((ClearConfigSettings) -> String)?
    let perform: (AccountContext, _ present: @escaping (ViewController, Any?) -> Void, _ push: @escaping (ViewController) -> Void) -> Void

    init(
        title: String,
        label: ((ClearConfigSettings) -> String)? = nil,
        perform: @escaping (AccountContext, _ present: @escaping (ViewController, Any?) -> Void, _ push: @escaping (ViewController) -> Void) -> Void
    ) {
        self.title = title
        self.label = label
        self.perform = perform
    }
}

// A row that opens a URL. `t.me` links are handed to the app's own resolver, so the channel
// opens as a chat rather than in a browser.
//
// Rendered like the rows that open a screen — tinted glyph on the left, destination on the right —
// so the hub reads as one list rather than a list with a plain button stapled to it.
private struct ClearLink {
    let title: String
    let label: String
    let icon: UIImage?
    let url: String
}

private enum ClearRow {
    case toggle(ClearToggle)
    case select(ClearSelect)
    case action(ClearAction)
    case link(ClearLink)
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
    case action(section: Int, index: Int, title: String, label: String?)
    case disclosure(section: Int, index: Int, title: String)
    case link(section: Int, index: Int, title: String, label: String)
    case reset(section: Int, index: Int, title: String)
    case footer(section: Int, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _),
             let .toggle(section, _, _, _, _, _),
             let .select(section, _, _, _),
             let .action(section, _, _, _),
             let .disclosure(section, _, _),
             let .link(section, _, _, _),
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
        case let .action(section, index, _, _):
            return section * 1000 + 10 + index
        case let .disclosure(section, index, _):
            return section * 1000 + 10 + index
        case let .link(section, index, _, _):
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
        case let (.action(ls, li, lt, ll), .action(rs, ri, rt, rl)):
            return ls == rs && li == ri && lt == rt && ll == rl
        case let (.disclosure(ls, li, lt), .disclosure(rs, ri, rt)):
            return ls == rs && li == ri && lt == rt
        case let (.link(ls, li, lt, ll), .link(rs, ri, rt, rl)):
            return ls == rs && li == ri && lt == rt && ll == rl
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
        case let .action(section, index, title, label):
            if let label {
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
            }
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
        case let .link(section, index, title, label):
            var icon: UIImage?
            if case let .link(link) = args.screen.sections[section].rows[index] {
                icon = link.icon
            }
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: icon,
                title: title,
                label: label,
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
                entries.append(.action(section: sectionIndex, index: rowIndex, title: action.title, label: action.label?(settings)))
            case let .link(link):
                entries.append(.link(section: sectionIndex, index: rowIndex, title: link.title, label: link.label))
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
    var openUrlImpl: ((String) -> Void)?
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
            case let .link(link):
                openUrlImpl?(link.url)
            case .toggle, .reset:
                break
            }
        },
        reset: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentImpl?(textAlertController(
                context: context,
                title: L("Reset Cleargram Settings", "Сбросить настройки Cleargram"),
                text: L(
                    "Every Cleargram option goes back to its default. Your chats, accounts and Telegram's own settings are not affected.",
                    "Все параметры Cleargram вернутся к значениям по умолчанию. Чаты, аккаунты и собственные настройки Telegram не затрагиваются."
                ),
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: L("Reset", "Сбросить"), action: {
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
    openUrlImpl = { [weak controller] url in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.openExternalUrl(
            context: context,
            urlContext: .generic,
            url: url,
            forceExternal: false,
            presentationData: presentationData,
            navigationController: controller?.navigationController as? NavigationController,
            dismissInput: {}
        )
    }
    askForRestartImpl = { [weak controller] in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(
                title: nil,
                text: L("Restart required to apply changes", "Для применения изменений нужен перезапуск"),
                timeout: nil,
                customUndoText: L("Restart Now", "Перезапустить")
            ),
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
    static let channel = renderSettingsIcon(name: "Item List/Icons/Channel", backgroundColors: [UIColor(rgb: 0x0088CC)])
}

// MARK: - The settings tree

private let clearChannelUsername = "@cleargramios"
private let clearChannelUrl = "https://t.me/cleargramios"

private func clearRootScreen() -> ClearScreen {
    return ClearScreen(title: "Cleargram", sections: [
        ClearSection(
            footer: L(
                "Everything is off by default — Cleargram starts out identical to stock Telegram.",
                "Всё выключено по умолчанию — вначале Cleargram ничем не отличается от обычного Telegram."
            ),
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
            rows: [
                .link(ClearLink(
                    title: L("Open Channel", "Перейти в канал"),
                    label: clearChannelUsername,
                    icon: ClearIcon.channel,
                    url: clearChannelUrl
                ))
            ]
        ),
        ClearSection(
            header: L("BACKUP", "РЕЗЕРВНАЯ КОПИЯ"),
            footer: L(
                "Opening a .cleargram file — from Files or a chat — shows what it will change before applying. Hidden chats, hidden messages and Telegram's own settings are never included.",
                "При открытии файла .cleargram (из «Файлов» или из чата) сначала видно, что он изменит. Скрытые чаты, скрытые сообщения и собственные настройки Telegram в него не входят."
            ),
            rows: [
                .action(ClearAction(title: L("Export Settings", "Экспорт настроек"), perform: { context, present, push in
                    ClearSettingsTransfer.presentExport(context: context, present: present, push: push, presentNative: { controller in
                        context.sharedContext.mainWindow?.presentNative(controller)
                    })
                })),
                .action(ClearAction(title: L("Import Settings", "Импорт настроек"), perform: { context, present, push in
                    ClearSettingsTransfer.presentImportPicker(context: context, present: present, presentNative: { controller in
                        context.sharedContext.mainWindow?.presentNative(controller)
                    }, push: push)
                })),
                .toggle(ClearToggle(
                    L("Import from Chats", "Импорт из чатов"),
                    .config(\.importSettingsFromChats),
                    subtitle: { _ in L("Tap a .cleargram file in a chat to import it", "Нажмите на файл .cleargram в чате, чтобы импортировать его") }
                ))
            ]
        ),
        ClearSection(
            footer: L("Asks for confirmation first.", "Сначала спросит подтверждение."),
            rows: [
                .reset(title: L("Reset All Settings", "Сбросить все настройки"))
            ]
        ),
        // Which build this is: the upstream release, the commit the patchset is pinned to and
        // the cleargram commit it was assembled from. Generated at sync time, see
        // ClearBuildInfo. Not translated — versions and hashes aren't UI text.
        ClearSection(
            footer: ClearBuildInfo.summary,
            rows: []
        )
    ])
}

private func clearAppearanceScreen() -> ClearScreen {
    return ClearScreen(title: L("Appearance", "Оформление"), icon: ClearIcon.appearance, sections: [
        ClearSection(
            header: L("GLASS", "СТЕКЛО"),
            footer: L(
                "Telegram's own experimental options. Fake Glass draws the iOS 26 glass look on devices without it; Force Clear Glass drops the tint so glass surfaces stay fully transparent.",
                "Экспериментальные параметры самого Telegram. «Имитация стекла» рисует вид iOS 26 на устройствах, где его нет; «Прозрачное стекло» убирает подкраску, оставляя поверхности прозрачными."
            ),
            rows: [
                .toggle(ClearToggle(L("Fake Glass", "Имитация стекла"), .experimental(\.fakeGlass))),
                .toggle(ClearToggle(L("Force Clear Glass", "Прозрачное стекло"), .experimental(\.forceClearGlass)))
            ]
        ),
        ClearSection(
            header: L("TEXT", "ТЕКСТ"),
            footer: L(
                "The largest message font (19 pt), in chats only. Requires a restart.",
                "Самый крупный шрифт сообщений (19 pt), только в чатах. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Larger Text in Chats", "Крупный текст в чатах"), .config(\.fontSizeOverride), requiresRestart: true))
            ]
        )
    ])
}

private func clearChatListScreen() -> ClearScreen {
    return ClearScreen(title: L("Chat List", "Список чатов"), icon: ClearIcon.chatList, sections: [
        ClearSection(
            header: L("ROWS", "СТРОКИ"),
            footer: L(
                "Smaller avatars and tighter spacing. Requires a restart.",
                "Аватары меньше, отступы плотнее. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Compact Rows", "Компактные строки"), .config(\.compactChatList), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: L("FOLDER TABS", "ВКЛАДКИ ПАПОК"),
            footer: L(
                "Hiding “All Chats” doesn't lose it — swiping right from the first folder still gets you there. Requires a restart.",
                "Скрытие «Все чаты» не убирает её совсем — свайп вправо с первой папки всё равно откроет её. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Compact Folder Names", "Компактные названия папок"), .config(\.compactFolderNames), requiresRestart: true)),
                .toggle(ClearToggle(L("Hide “All Chats” Tab", "Скрыть вкладку «Все чаты»"), .config(\.allChatsHidden), requiresRestart: true)),
                .toggle(ClearToggle.soon(
                    L("Shorten “All Chats” Title", "Укоротить название «Все чаты»"),
                    L("Planned: cut the tab title down to a fixed length.", "В планах: обрезать название вкладки до фиксированной длины.")
                ))
            ]
        ),
        ClearSection(
            header: L("STORIES", "ИСТОРИИ"),
            footer: L(
                "Removes stories everywhere — the chat-list strip, the ring around avatars, the profile tab and the camera buttons. Requires a restart.",
                "Убирает истории везде — ленту над списком чатов, кольцо вокруг аватаров, вкладку в профиле и кнопки камеры. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Stories", "Скрыть истории"), .config(\.hideStories), requiresRestart: true)),
                .toggle(ClearToggle(L("Disable Swipe to Story Camera", "Отключить свайп к камере историй"), .config(\.disableStoryCameraSwipe)))
            ]
        ),
        ClearSection(
            header: L("SWIPE", "СВАЙП"),
            rows: [
                .screen(clearSwipeActionsScreen())
            ]
        ),
        ClearSection(
            header: L("NOTICES", "УВЕДОМЛЕНИЯ"),
            footer: L(
                "Promotional notices are Premium offers, gift and photo prompts, and links Telegram pushes there. Security and balance warnings are always shown.",
                "Рекламные уведомления — это предложения Premium, напоминания про подарки и фото и ссылки, которые шлёт Telegram. Уведомления о безопасности и балансе показываются всегда."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Promotional Notices", "Скрыть рекламные уведомления"), .config(\.hideChatListPromoNotices))),
                .toggle(ClearToggle(L("Hide Birthday Notices", "Скрыть уведомления о днях рождения"), .config(\.hideChatListBirthdayNotices)))
            ]
        )
    ])
}

private func clearSwipeActionsScreen() -> ClearScreen {
    return ClearScreen(title: L("Swipe Actions", "Действия по свайпу"), sections: [
        ClearSection(
            header: L("SWIPE LEFT", "СВАЙП ВЛЕВО"),
            footer: L(
                "A full swipe fires the last action. An action only appears where Telegram already offered it.",
                "Полный свайп срабатывает на последнем действии. Действие появляется только там, где его уже предлагал Telegram."
            ),
            rows: [
                .toggle(ClearToggle(L("Mute", "Без звука"), .config(\.swipeActionMute), requiresRestart: true)),
                .toggle(ClearToggle(L("Delete", "Удалить"), .config(\.swipeActionDelete), requiresRestart: true)),
                .toggle(ClearToggle(L("Archive", "Архивировать"), .config(\.swipeActionArchive), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: L("SWIPE RIGHT", "СВАЙП ВПРАВО"),
            footer: L(
                "A full swipe fires the first action. Turning both off disables the right swipe.",
                "Полный свайп срабатывает на первом действии. Если выключить оба, свайп вправо отключается."
            ),
            rows: [
                .toggle(ClearToggle(L("Mark as Read / Unread", "Отметить как прочитанное"), .config(\.swipeActionRead), requiresRestart: true)),
                .toggle(ClearToggle(L("Pin", "Закрепить"), .config(\.swipeActionPin), requiresRestart: true))
            ]
        )
    ])
}

private func clearTabBarScreen() -> ClearScreen {
    return ClearScreen(title: L("Tab Bar", "Панель вкладок"), icon: ClearIcon.tabBar, sections: [
        ClearSection(
            header: L("TAB BAR", "ПАНЕЛЬ ВКЛАДОК"),
            dynamicFooter: { settings in
                if settings.hideTabBar {
                    return L(
                        "Settings and Contacts stay reachable from the chat list. The options below apply only while the bar is visible. Requires a restart.",
                        "Настройки и контакты остаются доступны из списка чатов. Параметры ниже действуют, только пока панель видна. Требуется перезапуск."
                    )
                } else {
                    return L(
                        "With the bar hidden, Settings and Contacts stay reachable from the chat list. Narrow shrinks the bar when you have fewer than four tabs. Requires a restart.",
                        "При скрытой панели настройки и контакты доступны из списка чатов. «Узкая панель» сжимает её при менее чем четырёх вкладках. Требуется перезапуск."
                    )
                }
            },
            rows: [
                .toggle(ClearToggle(L("Hide Tab Bar", "Скрыть панель вкладок"), .config(\.hideTabBar), requiresRestart: true)),
                .toggle(ClearToggle(L("Show Tab Names", "Показывать названия вкладок"), .config(\.showTabNames), isEnabled: { !$0.hideTabBar }, requiresRestart: true)),
                .toggle(ClearToggle(L("Narrow Tab Bar", "Узкая панель вкладок"), .config(\.narrowTabBar), isEnabled: { !$0.hideTabBar }, requiresRestart: true))
            ]
        ),
        ClearSection(
            header: L("TABS", "ВКЛАДКИ"),
            footer: L(
                "Turning off the Search tab removes search entirely — there's no other entry point yet. Hiding Contacts requires a restart.",
                "Выключение вкладки «Поиск» убирает поиск совсем — другого входа пока нет. Скрытие «Контактов» требует перезапуска."
            ),
            rows: [
                .toggle(ClearToggle(L("Search Tab", "Вкладка «Поиск»"), .config(\.tabBarSearchEnabled), isEnabled: { !$0.hideTabBar })),
                .toggle(ClearToggle(L("Hide Contacts Tab", "Скрыть вкладку «Контакты»"), .config(\.disableContactsTab), requiresRestart: true))
            ]
        )
    ])
}

private func clearChatsScreen() -> ClearScreen {
    return ClearScreen(title: L("Chats", "Чаты"), icon: ClearIcon.chats, sections: [
        ClearSection(
            header: L("MESSAGES", "СООБЩЕНИЯ"),
            rows: [
                .toggle(ClearToggle(L("Collapse Long Messages", "Сворачивать длинные сообщения"), .config(\.collapseLongMessages))),
                .toggle(ClearToggle(L("Original Time on Forwards", "Время оригинала у пересланных"), .config(\.showForwardedTime)))
            ]
        ),
        ClearSection(
            header: L("VOICE & VIDEO MESSAGES", "ГОЛОСОВЫЕ И ВИДЕОСООБЩЕНИЯ"),
            footer: L(
                "On-device transcription with Apple's speech recognition — the audio never leaves the device. Requires a restart.",
                "Расшифровка на устройстве через распознавание Apple — звук не покидает устройство. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(
                    L("Transcribe on This Device", "Расшифровка на устройстве"),
                    .experimental(\.localTranscription),
                    subtitle: { _ in L("Works without Premium", "Работает без Premium") },
                    requiresRestart: true
                )),
                .action(ClearAction(
                    title: L("Language", "Язык"),
                    label: { settings in clearTranscriptionLanguageLabel(settings.transcriptionLocales) },
                    perform: { context, _, push in
                        push(clearTranscriptionLanguageController(context: context))
                    }
                ))
            ]
        ),
        ClearSection(
            header: L("TIMESTAMPS", "ВРЕМЯ"),
            dynamicFooter: { settings in
                let sample = settings.secondsInMessages ? "12:30:45" : "12:30"
                return L(
                    "Timestamps under messages look like \(sample).",
                    "Время под сообщениями выглядит так: \(sample)."
                )
            },
            rows: [
                .toggle(ClearToggle(L("Show Seconds", "Показывать секунды"), .config(\.secondsInMessages))),
                .toggle(ClearToggle(L("Time on Service Messages", "Время у служебных сообщений"), .config(\.timeOnServiceMessages)))
            ]
        ),
        ClearSection(
            header: L("REACTIONS", "РЕАКЦИИ"),
            rows: [
                .toggle(ClearToggle(L("Hide Star Reaction", "Скрыть реакцию-звезду"), .config(\.hideStarReactionButton))),
                .toggle(ClearToggle(L("Hide Star Reaction Count", "Скрыть счётчик звёзд"), .config(\.hideStarReactionCount)))
            ]
        ),
        ClearSection(
            header: L("EDITING & DRAFTS", "РЕДАКТИРОВАНИЕ И ЧЕРНОВИКИ"),
            footer: L(
                "Drafts kept on this device are never uploaded — and won't follow you to another device.",
                "Черновики на этом устройстве никуда не отправляются — но и на другом устройстве не появятся."
            ),
            rows: [
                .toggle(ClearToggle(L("Double-Tap to Edit", "Двойное нажатие для правки"), .config(\.doubleTapToEdit))),
                .toggle(ClearToggle(L("Keep Drafts on This Device", "Черновики только на этом устройстве"), .config(\.blockCloudDrafts)))
            ]
        ),
        ClearSection(
            header: L("POLLS", "ОПРОСЫ"),
            footer: L(
                "Warns before a vote you can't change — a quiz, or a poll with revoting disabled — since that tap is final. Also warns before changing a vote the author can see.",
                "Предупреждает перед голосованием, которое нельзя изменить — в викторине или где запрещено переголосование, — ведь нажатие окончательное. Также предупреждает перед сменой голоса, которую видит автор."
            ),
            rows: [
                .toggle(ClearToggle(L("Confirm Poll Votes", "Подтверждать голосование"), .config(\.warnPollsRevote)))
            ]
        ),
        ClearSection(
            header: L("BOT KEYBOARDS", "КЛАВИАТУРЫ БОТОВ"),
            footer: L(
                "Hold a bot keyboard button to copy what it carries — a URL, a mini-app address, or a callback payload. Callback buttons need a longer hold so a tap still presses them.",
                "Удержание кнопки бота копирует то, что в ней зашито — URL, адрес мини-приложения или данные callback-кнопки. Callback-кнопки требуют удержания подольше, чтобы нажатие всё же срабатывало."
            ),
            rows: [
                .toggle(ClearToggle(L("Copy Button Data on Hold", "Копировать данные кнопки по удержанию"), .config(\.copyBotButtonUrl)))
            ]
        ),
        ClearSection(
            header: L("EMOJI KEYBOARD", "КЛАВИАТУРА ЭМОДЗИ"),
            footer: L(
                "Opens the emoji keyboard on the standard tab, not recent or custom sets.",
                "Открывает клавиатуру эмодзи на вкладке обычных эмодзи, а не на недавних или своих наборах."
            ),
            rows: [
                .toggle(ClearToggle(L("Standard Emoji First", "Сначала обычные эмодзи"), .config(\.defaultEmojisFirst)))
            ]
        ),
        ClearSection(
            header: L("SEARCH", "ПОИСК"),
            rows: [
                .toggle(ClearToggle.soon(
                    L("Search by User ID", "Поиск по ID пользователя"),
                    L(
                        "Planned: find a member's messages by numeric id where searching by @username doesn't work.",
                        "В планах: искать сообщения участника по числовому id там, где поиск по @имени не работает."
                    )
                ))
            ]
        )
    ])
}

private func clearChannelsScreen() -> ClearScreen {
    return ClearScreen(title: L("Channels", "Каналы"), icon: ClearIcon.channels, sections: [
        ClearSection(
            header: L("POSTS", "ПОСТЫ"),
            rows: [
                .toggle(ClearToggle(L("Full-Width Posts", "Посты во всю ширину"), .config(\.wideChannelPosts)))
            ]
        ),
        ClearSection(
            header: L("NAVIGATION", "НАВИГАЦИЯ"),
            rows: [
                .toggle(ClearToggle(L("Disable Scroll to Next Channel", "Не переходить к следующему каналу"), .config(\.disableScrollToNextChannel)))
            ]
        ),
        ClearSection(
            header: L("BOTTOM BAR", "НИЖНЯЯ ПАНЕЛЬ"),
            footer: L(
                "Removes the Mute/Join bar under a channel's posts. Joining then needs an invite link or a search result.",
                "Убирает панель «Без звука / Подписаться» под постами канала. Подписаться после этого можно по ссылке-приглашению или из поиска."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Bottom Action Bar", "Скрыть нижнюю панель действий"), .config(\.hideChannelBottomButton)))
            ]
        ),
        ClearSection(
            header: L("ADMIN", "АДМИНИСТРИРОВАНИЕ"),
            rows: [
                .toggle(ClearToggle.soon(
                    L("Better Recent Actions", "Улучшенные недавние действия"),
                    L(
                        "Planned: show edited messages as a diff in the admin log.",
                        "В планах: показывать изменённые сообщения в журнале администратора как различия."
                    )
                ))
            ]
        )
    ])
}

private func clearMediaScreen() -> ClearScreen {
    return ClearScreen(title: L("Media & Stickers", "Медиа и стикеры"), icon: ClearIcon.media, sections: [
        ClearSection(
            header: L("PHOTOS", "ФОТО"),
            footer: L(
                "Adds Copy to the “⋯” menu of the fullscreen viewer.",
                "Добавляет «Копировать» в меню «⋯» полноэкранного просмотра."
            ),
            rows: [
                .toggle(ClearToggle(L("Copy Image in Gallery", "Копировать фото в галерее"), .config(\.copyImageInGallery)))
            ]
        ),
        ClearSection(
            header: L("CAMERA", "КАМЕРА"),
            dynamicFooter: { settings in
                if settings.disableGalleryCamera {
                    return L(
                        "The camera tile is gone; the picker opens on your photos.",
                        "Плитка камеры убрана; меню вложений открывается на ваших фото."
                    )
                } else if settings.compactGalleryCamera {
                    return L(
                        "The camera tile becomes a static icon — no live preview, so no capture session or battery drain. Tapping it still opens the camera.",
                        "Плитка камеры становится статичным значком — без живого предпросмотра, а значит без запуска камеры и расхода батареи. Нажатие по-прежнему открывает камеру."
                    )
                } else {
                    return L(
                        "The picker's live camera preview can be hidden, or shrunk to a static icon with no capture session.",
                        "Живой предпросмотр камеры можно убрать или сжать до статичного значка без запуска камеры."
                    )
                }
            },
            rows: [
                .toggle(ClearToggle(L("Hide Camera in Picker", "Скрыть камеру в меню вложений"), .config(\.disableGalleryCamera))),
                .toggle(ClearToggle(L("Compact Camera Tile", "Компактная плитка камеры"), .config(\.compactGalleryCamera), isEnabled: { !$0.disableGalleryCamera })),
                .toggle(ClearToggle(L("Ask Which Camera for Video Messages", "Спрашивать камеру для видеосообщений"), .config(\.videoMessageCameraSelection)))
            ]
        ),
        ClearSection(
            header: L("VIDEO", "ВИДЕО"),
            footer: L(
                "A round-video button appears next to the GIF button in the media picker. It opens a crop-and-trim editor, then sends a square h.264 video capped at 60 seconds.",
                "Кнопка кружка появляется рядом с кнопкой GIF в выборе медиа. Она открывает редактор обрезки, затем отправляет квадратное видео h.264 длиной до 60 секунд."
            ),
            rows: [
                .toggle(ClearToggle(L("Send Video as Video Message", "Отправить видео как кружок"), .config(\.sendVideoAsCircle))),
                .toggle(ClearToggle.soon(
                    L("Audio Source for Video Messages", "Источник звука для видеосообщений"),
                    L(
                        "Planned: record through a Bluetooth or external mic.",
                        "В планах: запись через Bluetooth- или внешний микрофон."
                    )
                )),
                .toggle(ClearToggle.soon(
                    L("Original Video Quality", "Исходное качество видео"),
                    L("Planned: send a video without re-encoding.", "В планах: отправлять видео без перекодирования.")
                ))
            ]
        ),
        ClearSection(
            header: L("VIDEO MESSAGES", "КРУЖКИ"),
            rows: [
                .toggle(ClearToggle(
                    L("Square Video Message", "Квадратный кружок"),
                    .config(\.roundVideoKeepCorners),
                    subtitle: { _ in L(
                        "Keeps the corners instead of baking in the circular mask. Still an ordinary round video for everyone — the corners only show in the downloaded original.",
                        "Сохраняет углы вместо запекания круглой маски. Для всех это по-прежнему обычный кружок — углы видны только в скачанном оригинале."
                    ) }
                ))
            ]
        ),
        ClearSection(
            header: L("AUDIO", "АУДИО"),
            dynamicFooter: { settings in
                if settings.showAudioFormatBitrate {
                    return L(
                        "The music player subtitle reads like “Artist · ALAC 24-bit/96 kHz · 2304 kbps”.",
                        "Подпись в плеере выглядит так: «Исполнитель · ALAC 24-bit/96 kHz · 2304 kbps»."
                    )
                } else {
                    return L(
                        "Shows a track's codec and bitrate next to the artist. ALAC is told from AAC after the file downloads; while streaming, above 500 kbps is guessed lossless.",
                        "Показывает кодек и битрейт трека рядом с исполнителем. ALAC отличается от AAC после загрузки файла; при потоковом — выше 500 kbps считается lossless."
                    )
                }
            },
            rows: [
                .toggle(ClearToggle(L("Show Codec & Bitrate", "Показывать кодек и битрейт"), .config(\.showAudioFormatBitrate)))
            ]
        ),
        ClearSection(
            header: L("EQUALIZER", "ЭКВАЛАЙЗЕР"),
            footer: L(
                "Opens with a button in the music player.",
                "Открывается кнопкой в плеере."
            ),
            rows: [
                .toggle(ClearToggle(L("Equalizer", "Эквалайзер"), .config(\.equalizerEnabled)))
            ]
        ),
        ClearSection(
            header: L("LAST.FM", "LAST.FM"),
            footer: L(
                "Scrobbling writes what you play into your Last.fm history once a track is half done. “Now Playing” shows a live label on your profile. Sign in under Last.fm Account.",
                "Скробблинг записывает прослушанное в историю Last.fm, когда трек проигран наполовину. «Сейчас играет» показывает живую надпись в профиле. Вход — в «Аккаунте Last.fm»."
            ),
            rows: [
                .toggle(ClearToggle(
                    L("Scrobble to Last.fm", "Скробблинг в Last.fm"),
                    .config(\.lastFmScrobbling),
                    subtitle: { _ in
                        L(
                            "Needs your own API key: \(ClearLastFm.apiAccountUrl)",
                            "Нужен свой API-ключ: \(ClearLastFm.apiAccountUrl)"
                        )
                    }
                )),
                .toggle(ClearToggle(
                    L("Send “Now Playing”", "Отправлять «Сейчас играет»"),
                    .config(\.lastFmNowPlaying),
                    isEnabled: { $0.lastFmScrobbling }
                )),
                .action(ClearAction(
                    title: L("Last.fm Account", "Аккаунт Last.fm"),
                    // Not part of ClearConfigSettings — credentials live in their own key — but the
                    // in-memory mirror is current, and this row is rebuilt with the rest of the screen.
                    label: { _ in ClearLastFm.current().username },
                    perform: { context, _, push in
                        push(clearLastFmController(context: context))
                    }
                ))
            ]
        ),
        ClearSection(
            header: L("TRANSFERS", "ПЕРЕДАЧА ФАЙЛОВ"),
            footer: L(
                "Larger download and upload chunks. Faster on a stable connection; on a flaky one a failed chunk costs more to retry.",
                "Более крупные куски при скачивании и отправке. На стабильном соединении быстрее; на плохом повторить сорвавшийся кусок дороже."
            ),
            rows: [
                .toggle(ClearToggle(L("Faster File Transfer", "Ускоренная передача файлов"), .config(\.fasterFileLoad)))
            ]
        ),
        ClearSection(
            header: L("STICKERS", "СТИКЕРЫ"),
            footer: L(
                "Save to Photos covers static stickers only. Square Sticker Corners has no effect on a cut-out subject, which has no corners. Show Pack Owner opens the uploader's profile from a pack's “⋯” menu.",
                "«Сохранить в фото» работает только со статичными стикерами. «Квадратные углы» не влияют на вырезанный объект — у него нет углов. «Владелец набора» открывает профиль загрузившего из меню «⋯» набора."
            ),
            rows: [
                .toggle(ClearToggle(L("Save Sticker to Photos", "Сохранять стикер в фото"), .config(\.saveStickerToPhotos))),
                .toggle(ClearToggle(L("Square Sticker Corners", "Квадратные углы стикеров"), .config(\.flatStickerCorners))),
                .toggle(ClearToggle(L("Show Pack Owner", "Показывать владельца набора"), .config(\.showPackOwner)))
            ]
        ),
        ClearSection(
            header: L("RECENT STICKERS", "НЕДАВНИЕ СТИКЕРЫ"),
            footer: L(
                "Telegram caps recent stickers at 20; Cleargram keeps the extras locally. They fill in as you use stickers and don't sync to other devices.",
                "Telegram держит не больше 20 недавних стикеров; Cleargram сохраняет лишние локально. Они набираются по мере использования и не синхронизируются на другие устройства."
            ),
            rows: [
                .select(ClearSelect(
                    title: L("Keep", "Хранить"),
                    keyPath: \.recentStickersLimit,
                    options: [(0, L("Default (20)", "По умолчанию (20)")), (30, "30"), (50, "50"), (100, "100"), (200, "200")]
                ))
            ]
        )
    ])
}

private func clearLinksScreen() -> ClearScreen {
    return ClearScreen(title: L("Links", "Ссылки"), icon: ClearIcon.links, sections: [
        ClearSection(
            header: L("TRACKING", "ОТСЛЕЖИВАНИЕ"),
            dynamicFooter: { settings in
                if settings.stripTrackingParams {
                    return L(
                        "youtu.be/dQw4w9WgXcQ?si=…\nbecomes youtu.be/dQw4w9WgXcQ\n\nApplied to links in messages you send, and to Copy on a link.",
                        "youtu.be/dQw4w9WgXcQ?si=…\nстанет youtu.be/dQw4w9WgXcQ\n\nПрименяется к ссылкам в отправляемых сообщениях и к «Копировать» у ссылки."
                    )
                } else {
                    return L(
                        "Removes utm_*, fbclid, si and similar parameters.\n\nApplied to links in messages you send, and to Copy on a link.",
                        "Убирает параметры utm_*, fbclid, si и подобные.\n\nПрименяется к ссылкам в отправляемых сообщениях и к «Копировать» у ссылки."
                    )
                }
            },
            rows: [
                .toggle(ClearToggle(L("Remove Tracking", "Убирать трекинг"), .config(\.stripTrackingParams)))
            ]
        ),
        ClearSection(
            header: L("PREVIEWS", "ПРЕДПРОСМОТР"),
            footer: L(
                "Sends links through a mirror that lets Telegram build a preview.\n\nX, Instagram, TikTok, Reddit, Bluesky, Pixiv.",
                "Отправляет ссылки через зеркало, с которым Telegram может построить предпросмотр.\n\nX, Instagram, TikTok, Reddit, Bluesky, Pixiv."
            ),
            rows: [
                .toggle(ClearToggle(L("Fix Previews", "Чинить предпросмотр"), .config(\.replacePreviewLinks)))
            ]
        ),
        ClearSection(
            header: L("TELEGRAM LINKS", "ССЫЛКИ TELEGRAM"),
            footer: L(
                "Asks before opening a t.me or tg:// link — those can trigger unwanted actions.",
                "Спрашивает перед открытием ссылки t.me или tg:// — такие ссылки могут выполнять нежелательные действия."
            ),
            rows: [
                .toggle(ClearToggle(L("Confirm Telegram Links", "Подтверждать ссылки Telegram"), .config(\.confirmInternalLinks)))
            ]
        )
    ])
}

private func clearMessageMenuScreen() -> ClearScreen {
    return ClearScreen(title: L("Message Menu", "Меню сообщения"), icon: ClearIcon.messageMenu, sections: [
        ClearSection(
            header: L("HIDE ACTIONS", "СКРЫТЬ ДЕЙСТВИЯ"),
            footer: L(
                "Hidden actions stay reachable elsewhere — swipe still replies, and selection starts from the chat's own menu.",
                "Скрытые действия остаются доступны в других местах — свайп по-прежнему отвечает, а выбор запускается из меню чата."
            ),
            rows: [
                .toggle(ClearToggle(L("Reply", "Ответить"), .config(\.hideContextMenuReply))),
                .toggle(ClearToggle(L("Pin", "Закрепить"), .config(\.hideContextMenuPin))),
                .toggle(ClearToggle(L("Forward", "Переслать"), .config(\.hideContextMenuForward))),
                .toggle(ClearToggle(L("Report", "Пожаловаться"), .config(\.hideContextMenuReport))),
                .toggle(ClearToggle(L("Select", "Выбрать"), .config(\.hideContextMenuSelect)))
            ]
        )
    ])
}

private func clearProfileScreen() -> ClearScreen {
    return ClearScreen(title: L("Profile", "Профиль"), icon: ClearIcon.profile, sections: [
        ClearSection(
            header: L("PROFILES", "ПРОФИЛИ"),
            footer: L(
                "Tap the row to copy the value; hold a group or channel id to copy the bot-API form (-100…).",
                "Нажатие копирует значение; удержание ID группы или канала копирует форму Bot API (-100…)."
            ),
            rows: [
                .toggle(ClearToggle(L("Show ID", "Показывать ID"), .config(\.showProfileId))),
                .toggle(ClearToggle(L("Show Datacenter", "Показывать датацентр"), .config(\.showDC)))
            ]
        ),
        ClearSection(
            header: L("ACCOUNT ORIGIN", "ПРОИСХОЖДЕНИЕ АККАУНТА"),
            footer: L(
                "Telegram sends this only with the first message from a non-contact, so the rows often don't appear. Month precision only.",
                "Telegram присылает это только с первым сообщением от не-контакта, поэтому строки часто не появляются. Точность — до месяца."
            ),
            rows: [
                .toggle(ClearToggle(L("Show Registration Date", "Показывать дату регистрации"), .config(\.showRegistrationDate))),
                .toggle(ClearToggle(L("Show Phone Country", "Показывать страну номера"), .config(\.showPhoneCountry)))
            ]
        ),
        ClearSection(
            header: L("YOUR PROFILE", "ВАШ ПРОФИЛЬ"),
            footer: L(
                "Hides your number in Settings only — it stays visible to whoever you share it with. Requires a restart.",
                "Скрывает номер только в настройках — тем, кому вы его показываете, он остаётся виден. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide My Phone Number", "Скрыть мой номер телефона"), .config(\.hidePhoneInSettings), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: L("ACTIONS", "ДЕЙСТВИЯ"),
            rows: [
                .toggle(ClearToggle(L("Hide Call Button", "Скрыть кнопку звонка"), .config(\.disableCallsButton)))
            ]
        )
    ])
}

private func clearPrivacyScreen() -> ClearScreen {
    return ClearScreen(title: L("Privacy", "Конфиденциальность"), icon: ClearIcon.privacy, sections: [
        ClearSection(
            header: L("CONFIRMATIONS", "ПОДТВЕРЖДЕНИЯ"),
            rows: [
                .toggle(ClearToggle(L("Confirm Calls", "Подтверждать звонки"), .config(\.confirmCalls)))
            ]
        ),
        ClearSection(
            header: L("FACE ID / TOUCH ID", "FACE ID / TOUCH ID"),
            footer: L(
                "If biometry is unavailable, the device passcode is asked instead; with no passcode, the action is blocked.",
                "Если биометрия недоступна, запрашивается код-пароль устройства; если его нет — действие не выполняется."
            ),
            rows: [
                .toggle(ClearToggle(L("Confirm Delete Chat", "Подтверждать удаление чата"), .config(\.biometricConfirmDeleteChat))),
                .toggle(ClearToggle(L("Confirm Clear History", "Подтверждать очистку истории"), .config(\.biometricConfirmClearHistory))),
                .toggle(ClearToggle(L("Confirm Log Out", "Подтверждать выход из аккаунта"), .config(\.biometricConfirmLogout)))
            ]
        ),
        ClearSection(
            header: L("PARANOIA", "ПАРАНОЙЯ"),
            rows: [
                .toggle(ClearToggle.soon(
                    L("Paranoia Mode", "Режим паранойи"),
                    L(
                        "Planned: keep hidden chats out of contacts, recent calls, search and the share sheet too.",
                        "В планах: убирать скрытые чаты также из контактов, недавних звонков, поиска и меню «Поделиться»."
                    )
                ))
            ]
        )
    ])
}

private func clearDebloatScreen() -> ClearScreen {
    return ClearScreen(title: L("Debloat", "Чистка интерфейса"), icon: ClearIcon.debloat, sections: [
        ClearSection(
            header: L("PROMOTION", "ПРОДВИЖЕНИЕ"),
            footer: L(
                "The similar-channels block appears right after you join a channel.",
                "Блок похожих каналов появляется сразу после подписки на канал."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Similar Channels", "Скрыть похожие каналы"), .config(\.hideSimilarChannels)))
            ]
        ),
        ClearSection(
            header: L("AI", "ИИ"),
            footer: L(
                "Removes the summarize button, the AI compose buttons and the AI entry in the attachment menu.",
                "Убирает кнопку пересказа, кнопки ИИ-набора и пункт ИИ в меню вложений."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide AI Features", "Скрыть функции ИИ"), .config(\.hideAiFeatures)))
            ]
        ),
        ClearSection(
            header: L("MONETIZATION", "МОНЕТИЗАЦИЯ"),
            rows: [
                .toggle(ClearToggle.soon(
                    L("Hide Premium, Stars & Gifts", "Скрыть Premium, звёзды и подарки"),
                    L(
                        "Planned: strip the Premium upsell, Stars, gifts, boosts and collectibles from the interface.",
                        "В планах: убрать из интерфейса рекламу Premium, звёзды, подарки, бусты и коллекционные предметы."
                    )
                ))
            ]
        ),
        ClearSection(
            header: L("ADMIN", "АДМИНИСТРИРОВАНИЕ"),
            footer: L(
                "Hides the “N want to join” banner admins see. The requests themselves are untouched.",
                "Скрывает плашку «N хотят вступить» для админов. Сами заявки не затрагиваются."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Join Requests Banner", "Скрыть плашку заявок на вступление"), .config(\.hideChannelJoinRequests)))
            ]
        )
    ])
}
