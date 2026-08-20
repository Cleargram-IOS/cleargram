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
                "Every option is off by default — with nothing enabled Cleargram behaves exactly like stock Telegram.",
                "Все параметры по умолчанию выключены — пока ничего не включено, Cleargram ведёт себя ровно как обычный Telegram."
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
                "Exports every Cleargram option you've changed into a small .cleargram file you can keep or send to someone. Opening one — from Files or from a chat — shows exactly what it would change before anything is applied. Hidden chats, hidden messages and Telegram's own settings are never included.",
                "Сохраняет все изменённые параметры Cleargram в небольшой файл .cleargram — его можно оставить себе или отправить кому-то. При открытии такого файла (из «Файлов» или из чата) сначала показывается, что именно он изменит. Скрытые чаты, скрытые сообщения и собственные настройки Telegram в него не попадают."
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
                "Two of Telegram's own experimental options, surfaced here. Fake Glass draws the iOS 26 glass look on devices that don't support the real thing; Force Clear Glass drops the tint from glass surfaces so they stay fully transparent.",
                "Два экспериментальных параметра самого Telegram, вынесенных сюда. «Имитация стекла» рисует внешний вид iOS 26 на устройствах, где настоящего эффекта нет; «Прозрачное стекло» убирает подкраску стеклянных поверхностей, оставляя их полностью прозрачными."
            ),
            rows: [
                .toggle(ClearToggle(L("Fake Glass", "Имитация стекла"), .experimental(\.fakeGlass))),
                .toggle(ClearToggle(L("Force Clear Glass", "Прозрачное стекло"), .experimental(\.forceClearGlass)))
            ]
        ),
        ClearSection(
            header: L("TEXT", "ТЕКСТ"),
            footer: L(
                "Uses the largest message font (19 pt) in chats, leaving the chat list and Settings at their normal size. Requires a restart.",
                "Использует самый крупный шрифт сообщений (19 pt) в чатах, оставляя список чатов и настройки прежнего размера. Требуется перезапуск."
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
                "Compact rows use a smaller avatar and tighter spacing, so more chats fit on screen. Requires a restart.",
                "Компактные строки используют аватар поменьше и плотные отступы, поэтому на экран помещается больше чатов. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Compact Rows", "Компактные строки"), .config(\.compactChatList), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: L("FOLDER TABS", "ВКЛАДКИ ПАПОК"),
            footer: L(
                "Shrinks the folder tabs above the chat list and lets you drop the “All Chats” tab — swiping right from the first folder still gets you there. Requires a restart.",
                "Уменьшает вкладки папок над списком чатов и позволяет убрать вкладку «Все чаты» — свайп вправо с первой папки всё равно открывает её. Требуется перезапуск."
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
                "Removes stories everywhere: the strip above the chat list, the coloured ring around avatars, the Stories tab in profiles and the story camera buttons. Requires a restart.",
                "Убирает истории везде: ленту над списком чатов, цветное кольцо вокруг аватаров, вкладку «Истории» в профилях и кнопки камеры историй. Требуется перезапуск."
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
                "The banner above the chat list. Promotional notices are Premium offers, gift and profile-photo prompts and whatever link Telegram decides to push there; birthday notices are your contacts' birthdays. New-login reviews, account freeze, password setup and a low Stars balance are always shown — those are the ones you can't afford to miss.",
                "Плашка над списком чатов. Рекламные уведомления — это предложения Premium, напоминания про подарки и фото профиля и любые ссылки, которые Telegram решит туда показать; уведомления о днях рождения — дни рождения ваших контактов. Проверка нового входа, заморозка аккаунта, настройка пароля и низкий баланс звёзд показываются всегда — их пропускать нельзя."
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
                "Actions revealed when you drag a chat to the left. A full swipe fires the last one — with Archive on that is Archive, exactly like stock. An action only ever appears where Telegram already offered it; turning one off never moves it somewhere else.",
                "Действия, которые появляются, если потянуть чат влево. Полный свайп срабатывает на последнем из них — при включённом «Архивировать» это архивация, ровно как в оригинале. Действие появляется только там, где его уже предлагал Telegram; выключение никогда не переносит его в другое место."
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
                "Actions revealed when you drag a chat to the right. A full swipe fires the first one. Turning both off disables that swipe direction entirely.",
                "Действия, которые появляются, если потянуть чат вправо. Полный свайп срабатывает на первом из них. Если выключить оба, свайп в эту сторону отключается совсем."
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
                        "The bar at the bottom of the screen is gone; Settings and Contacts stay reachable from the chat list. The options below apply only while the bar is visible. Requires a restart.",
                        "Панель внизу экрана убрана; настройки и контакты по-прежнему доступны из списка чатов. Параметры ниже действуют, только пока панель видна. Требуется перезапуск."
                    )
                } else {
                    return L(
                        "Hiding the bar frees the bottom of the screen — Settings and Contacts stay reachable from the chat list. Narrow shrinks the bar when you have fewer than four tabs, so it hugs the icons instead of stretching across the screen. Requires a restart.",
                        "Скрытие панели освобождает низ экрана — настройки и контакты остаются доступны из списка чатов. «Узкая панель» сжимает её, когда вкладок меньше четырёх, и панель облегает значки вместо того, чтобы растягиваться на всю ширину. Требуется перезапуск."
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
                "Turning the Search tab off removes search from the tab bar entirely — there is no other entry point for it yet. Hiding the Contacts tab requires a restart.",
                "Выключение вкладки «Поиск» убирает поиск из панели вкладок целиком — другого входа в него пока нет. Скрытие вкладки «Контакты» требует перезапуска."
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
            footer: L(
                "Very long messages get a “Show more” button instead of filling the whole screen. Forwarded messages can show when the original was sent, next to who sent it.",
                "Очень длинные сообщения получают кнопку «Показать ещё» вместо того, чтобы занимать весь экран. У пересланных сообщений рядом с автором может показываться время отправки оригинала."
            ),
            rows: [
                .toggle(ClearToggle(L("Collapse Long Messages", "Сворачивать длинные сообщения"), .config(\.collapseLongMessages))),
                .toggle(ClearToggle(L("Original Time on Forwards", "Время оригинала у пересланных"), .config(\.showForwardedTime)))
            ]
        ),
        ClearSection(
            header: L("VOICE & VIDEO MESSAGES", "ГОЛОСОВЫЕ И ВИДЕОСООБЩЕНИЯ"),
            footer: L(
                "Transcribes voice and video messages on this device with Apple's speech recognition. The audio is never sent anywhere. Requires a restart.",
                "Расшифровывает голосовые и видеосообщения на устройстве через распознавание речи Apple. Звук никуда не отправляется. Требуется перезапуск."
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
                    "Timestamps under messages look like \(sample). Service messages (“X added Y”) normally carry no time at all.",
                    "Время под сообщениями выглядит так: \(sample). У служебных сообщений («X добавил Y») времени обычно нет вообще."
                )
            },
            rows: [
                .toggle(ClearToggle(L("Show Seconds", "Показывать секунды"), .config(\.secondsInMessages))),
                .toggle(ClearToggle(L("Time on Service Messages", "Время у служебных сообщений"), .config(\.timeOnServiceMessages)))
            ]
        ),
        ClearSection(
            header: L("REACTIONS", "РЕАКЦИИ"),
            footer: L(
                "Removes the paid Star reaction from the reaction bar, and its counter from messages that already have one.",
                "Убирает платную реакцию-звезду из панели реакций, а её счётчик — из сообщений, где она уже стоит."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Star Reaction", "Скрыть реакцию-звезду"), .config(\.hideStarReactionButton))),
                .toggle(ClearToggle(L("Hide Star Reaction Count", "Скрыть счётчик звёзд"), .config(\.hideStarReactionCount)))
            ]
        ),
        ClearSection(
            header: L("EDITING & DRAFTS", "РЕДАКТИРОВАНИЕ И ЧЕРНОВИКИ"),
            footer: L(
                "Double-tap your own message to open the editor, instead of holding it and picking Edit. With cloud drafts off, text you started typing stays on this device and is never uploaded — it won't follow you to another device either.",
                "Двойное нажатие по своему сообщению открывает редактор — не нужно удерживать его и выбирать «Изменить». Если облачные черновики выключены, начатый текст остаётся на этом устройстве и никуда не отправляется — но и на другом устройстве не появится."
            ),
            rows: [
                .toggle(ClearToggle(L("Double-Tap to Edit", "Двойное нажатие для правки"), .config(\.doubleTapToEdit))),
                .toggle(ClearToggle(L("Keep Drafts on This Device", "Черновики только на этом устройстве"), .config(\.blockCloudDrafts)))
            ]
        ),
        ClearSection(
            header: L("POLLS", "ОПРОСЫ"),
            footer: L(
                "Warns before you vote in a poll that cannot be revoted — a quiz, or one whose author disabled changing the vote — because that tap is final and nothing in the poll says so. Also asks before changing a vote you already cast, which the poll's author can see.",
                "Предупреждает перед голосованием в опросе, где нельзя переголосовать — в викторине или там, где автор запретил менять голос, — потому что нажатие окончательное, а в самом опросе об этом ничего не сказано. Также спрашивает перед сменой уже отданного голоса, которую видит автор опроса."
            ),
            rows: [
                .toggle(ClearToggle(L("Confirm Poll Votes", "Подтверждать голосование"), .config(\.warnPollsRevote)))
            ]
        ),
        ClearSection(
            header: L("BOT KEYBOARDS", "КЛАВИАТУРЫ БОТОВ"),
            footer: L(
                "Hold a bot keyboard button to copy what it carries: the URL for link buttons — login buttons carry a fallback URL that stock Telegram never shows, web-app buttons the mini-app URL — and the payload the bot receives for callback buttons. Plain link buttons already offer Copy on hold and are left alone.\n\nCallback buttons need a longer hold (0.8s) so that a slow tap still presses the button.",
                "Удержание кнопки бота копирует то, что в ней зашито: URL у кнопок со ссылкой (у кнопок входа это запасной URL, который обычный Telegram нигде не показывает, у кнопок мини-приложений — адрес самого приложения) и данные, которые получает бот, — у callback-кнопок. Обычные кнопки-ссылки и так предлагают «Копировать» по удержанию, их это не касается.\n\nCallback-кнопки требуют удержания подольше (0,8 с), чтобы медленное нажатие всё же срабатывало как нажатие кнопки."
            ),
            rows: [
                .toggle(ClearToggle(L("Copy Button Data on Hold", "Копировать данные кнопки по удержанию"), .config(\.copyBotButtonUrl)))
            ]
        ),
        ClearSection(
            header: L("EMOJI KEYBOARD", "КЛАВИАТУРА ЭМОДЗИ"),
            footer: L(
                "Opens the emoji keyboard on the standard emoji tab instead of recent or custom sets.",
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
                        "Planned: find a member's messages by numeric id in groups that hide their member list, where searching by @username fails.",
                        "В планах: искать сообщения участника по числовому id в группах со скрытым списком участников, где поиск по @имени не работает."
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
            footer: L(
                "Full-width posts drop the bubble and stretch channel messages across the screen.",
                "Посты во всю ширину убирают пузырь и растягивают сообщения канала на весь экран."
            ),
            rows: [
                .toggle(ClearToggle(L("Full-Width Posts", "Посты во всю ширину"), .config(\.wideChannelPosts)))
            ]
        ),
        ClearSection(
            header: L("NAVIGATION", "НАВИГАЦИЯ"),
            footer: L(
                "Scrolling past the last post no longer pulls you into the next channel.",
                "Прокрутка за последний пост больше не перебрасывает в следующий канал."
            ),
            rows: [
                .toggle(ClearToggle(L("Disable Scroll to Next Channel", "Не переходить к следующему каналу"), .config(\.disableScrollToNextChannel)))
            ]
        ),
        ClearSection(
            header: L("BOTTOM BAR", "НИЖНЯЯ ПАНЕЛЬ"),
            footer: L(
                "Removes the bar under a channel's posts — Mute / Unmute once you've joined, Join before that. Selecting messages and in-chat search still get their panels. Joining a channel then needs an invite link or the search result.",
                "Убирает панель под постами канала — «Вкл./Выкл. звук» после подписки и «Подписаться» до неё. Панели выбора сообщений и поиска по чату остаются. Подписаться после этого можно по ссылке-приглашению или из результатов поиска."
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
                        "Planned: show edited messages as a diff in the admin log, instead of truncating the original.",
                        "В планах: показывать изменённые сообщения в журнале администратора как различия, а не обрезать оригинал."
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
                "Adds Copy to the “⋯” menu of the fullscreen viewer. Stock Telegram only copies from the message menu, and only when the message holds a single photo without a caption.",
                "Добавляет «Копировать» в меню «⋯» полноэкранного просмотра. Обычный Telegram копирует только из меню сообщения и только если в сообщении одно фото без подписи."
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
                        "The camera tile is gone from the attachment picker; the grid starts with your photos. Also lets you pick the front or back camera before recording a video message.",
                        "Плитка камеры убрана из меню вложений, сетка начинается сразу с ваших фото. Также позволяет выбрать фронтальную или основную камеру перед записью видеосообщения."
                    )
                } else if settings.compactGalleryCamera {
                    return L(
                        "The camera tile in the attachment picker is one square cell with a plain icon instead of two cells of live preview — no capture session runs while you browse, so no battery drain and no camera-in-use indicator. Tapping it still opens the camera. Also lets you pick the front or back camera before recording a video message.",
                        "Плитка камеры в меню вложений — одна квадратная ячейка со значком вместо двух ячеек живого предпросмотра: пока вы листаете, камера не запускается, а значит нет ни расхода батареи, ни индикатора использования камеры. Нажатие по-прежнему открывает камеру. Также позволяет выбрать фронтальную или основную камеру перед записью видеосообщения."
                    )
                } else {
                    return L(
                        "The attachment picker normally runs a live camera preview two cells tall. Hide it entirely, or shrink it to a single cell with a static icon and no capture session. Also lets you pick the front or back camera before recording a video message.",
                        "В меню вложений обычно работает живой предпросмотр камеры высотой в две ячейки. Его можно убрать совсем или сжать до одной ячейки со статичным значком и без запуска камеры. Также позволяет выбрать фронтальную или основную камеру перед записью видеосообщения."
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
                "A round-video button appears next to the GIF button while previewing a video in the media picker. It opens a circular crop-and-trim editor, then sends: the video is cropped to a square, re-encoded to h.264 and trimmed to 60 seconds — the same conversion the round-video camera uses, including the size set under Video Messages.",
                "Кнопка кружка появляется рядом с кнопкой GIF при просмотре видео в выборе медиа. Она открывает круглый редактор обрезки и подрезки, а затем отправляет: видео обрезается в квадрат, перекодируется в h.264 и укорачивается до 60 секунд — то же преобразование, что и у камеры кружков, включая размер, заданный в разделе «Кружки»."
            ),
            rows: [
                .toggle(ClearToggle(L("Send Video as Video Message", "Отправить видео как кружок"), .config(\.sendVideoAsCircle))),
                .toggle(ClearToggle.soon(
                    L("Audio Source for Video Messages", "Источник звука для видеосообщений"),
                    L(
                        "Planned: record a video message through a Bluetooth or external mic instead of the built-in one.",
                        "В планах: записывать видеосообщение через Bluetooth- или внешний микрофон вместо встроенного."
                    )
                )),
                .toggle(ClearToggle.soon(
                    L("Original Video Quality", "Исходное качество видео"),
                    L("Planned: send a video as-is, skipping re-encoding.", "В планах: отправлять видео как есть, без перекодирования.")
                ))
            ]
        ),
        ClearSection(
            header: L("VIDEO MESSAGES", "КРУЖКИ"),
            footer: L(
                "Stock records a video message at 400×400 and 30 fps, then bakes the circular mask into the pixels before uploading. The round shape itself is drawn by whoever reads the message, from a flag on it, so these change only what this device records. Quality is worth raising: while playing, a video message is blown up to about 404 pt — roughly 1200 px on a modern screen. It is not a free dial, though, because the server refuses to keep a video message round above some size and quietly turns it into an ordinary video; if that happens, step back down.",
                "Обычный Telegram записывает кружок в 400×400 и 30 кадрах/с, после чего запекает круглую маску прямо в пиксели и только потом загружает. Сам круг рисует тот, кто читает сообщение, по флагу на нём, так что эти настройки меняют только то, что записывает это устройство. Качество поднять стоит: при проигрывании кружок раздувается примерно до 404 pt — около 1200 px на современном экране. Но это не свободная ручка: выше некоторого размера сервер отказывается держать сообщение кружком и молча превращает его в обычное видео — если так вышло, вернитесь на шаг назад."
            ),
            rows: [
                .toggle(ClearToggle(
                    L("60 FPS", "60 кадров/с"),
                    .config(\.roundVideo60Fps),
                    subtitle: { _ in L(
                        "Turns off the two-camera mode while recording a video message, because 60 fps needs the single-camera session — so no live front/back switch mid-recording. In exchange the back camera becomes the full multi-lens one, so pinching in now reaches the ultra-wide. Costs more processing too; an older device may drop frames instead.",
                        "Отключает двухкамерный режим при записи кружка: 60 кадров/с требуют одиночной сессии, поэтому переключаться между камерами на ходу больше не выйдет. Взамен задняя камера становится полной многолинзовой, так что щипком внутрь теперь доступен ультраширик. Требует и больше вычислений — старое устройство может вместо этого ронять кадры."
                    ) }
                )),
                .select(ClearSelect(
                    title: L("Quality", "Качество"),
                    keyPath: \.roundVideoSide,
                    options: [(0, L("Default (400)", "Стандартное (400)")), (512, "512×512"), (640, "640×640")]
                )),
                .toggle(ClearToggle(
                    L("Square Video Message", "Квадратный кружок"),
                    .config(\.roundVideoKeepCorners),
                    subtitle: { _ in L(
                        "Stops the circular mask from being baked in, so the corners keep real picture. It stays an ordinary video message for everyone — every client draws the circle itself. The corners only surface for whoever downloads the original file.",
                        "Не запекает круглую маску, и углы сохраняют реальную картинку. Для всех это по-прежнему обычный кружок — круг каждый клиент рисует сам. Углы видит только тот, кто скачает оригинал файла."
                    ) }
                )),
                .toggle(ClearToggle(
                    L("Save without Watermark", "Сохранять без водяного знака"),
                    .config(\.roundVideoSaveUnmasked),
                    subtitle: { _ in L(
                        "Adds a second save entry to a video message's menu. It re-encodes the file with everything outside the visible circle blacked out — which is where senders put branding. Note that this means it applies a circular mask of its own, so it is not the way to download a square video message at its full extent: use the plain Save to Gallery for that.",
                        "Добавляет в меню кружка второй пункт сохранения. Он перекодирует файл, заливая чёрным всё, что вне видимого круга, — именно туда отправители помещают свои обозначения. Учтите, что тем самым он накладывает собственную круглую маску, поэтому скачать квадратный кружок целиком через него не выйдет: для этого используйте обычное «Сохранить в галерею»."
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
                        "Shows the codec and bitrate of a track next to the artist in the music player. ALAC is told apart from AAC by reading the container once the file has finished downloading — while it is still streaming, anything above 500 kbps is taken as lossless.",
                        "Показывает кодек и битрейт трека рядом с исполнителем в плеере. ALAC отличается от AAC по контейнеру, который читается после полной загрузки файла; пока идёт потоковое воспроизведение, всё выше 500 kbps считается lossless."
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
                "Scrobbling writes the music you play in Telegram into your Last.fm history — a track counts once it is half played. “Now Playing” adds a live label on your Last.fm profile while the track is playing; the history is written either way. Sign in under Last.fm Account.",
                "Скробблинг записывает музыку, которую вы слушаете в Telegram, в историю Last.fm — трек засчитывается, когда проигран наполовину. «Сейчас играет» добавляет сверху живую надпись в профиле Last.fm, пока трек играет; история пишется в любом случае. Вход — в «Аккаунте Last.fm»."
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
                    subtitle: { _ in L("On top of the history: a label on your Last.fm profile", "Вдобавок к истории: надпись в профиле Last.fm") },
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
                "Downloads and uploads in larger chunks (1 MB down, 512 KB up instead of 512/256 KB). Faster on a stable connection; on a flaky one a failed chunk costs more to retry.",
                "Скачивает и отправляет файлы более крупными кусками (1 МБ на приём и 512 КБ на отправку вместо 512/256 КБ). На стабильном соединении быстрее; на плохом повторная отправка сорвавшегося куска обходится дороже."
            ),
            rows: [
                .toggle(ClearToggle(L("Faster File Transfer", "Ускоренная передача файлов"), .config(\.fasterFileLoad)))
            ]
        ),
        ClearSection(
            header: L("STICKERS", "СТИКЕРЫ"),
            footer: L(
                "Save to Photos appears in the context menu of static stickers. Square Sticker Corners drops the 12.5% rounding from the sticker editor's frame, from a photo you insert into it and from the exported file — a cut-out subject has no corners to square, so it looks the same either way. Show Pack Owner adds an entry to a sticker pack's “⋯” menu that opens the profile of whoever uploaded it.",
                "«Сохранить в фото» появляется в контекстном меню статичных стикеров. «Квадратные углы стикеров» убирают скругление в 12,5% у рамки редактора стикеров, у вставленного в неё фото и у готового файла — у вырезанного объекта углов нет, поэтому он выглядит одинаково в обоих случаях. «Владелец набора» добавляет в меню «⋯» набора стикеров пункт, открывающий профиль того, кто его загрузил."
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
                "Telegram keeps the last 20 stickers you used, and the cloud copy gets trimmed back to that on every sync. Cleargram keeps the ones the server drops, so the Recent row can grow past it. The list fills up as you use stickers — nothing is restored retroactively, the extras live on this device only, and clearing recent stickers still clears everything.",
                "Telegram хранит последние 20 использованных стикеров и при каждой синхронизации обрезает облачную копию до этого числа. Cleargram сохраняет те, что сервер отбрасывает, поэтому ряд недавних может стать длиннее. Список наполняется по мере использования — задним числом ничего не восстанавливается, лишние стикеры живут только на этом устройстве, а очистка недавних по-прежнему стирает всё."
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
                "Removes entries from the menu that appears when you hold a message. What you hide here stays reachable elsewhere — swipe still replies, and selection still starts from the chat's own menu.",
                "Убирает пункты из меню, которое появляется при удержании сообщения. Скрытое здесь остаётся доступным в других местах: свайп по-прежнему отвечает, а выбор сообщений запускается из меню самого чата."
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
                "Adds the numeric id and the datacenter under the profile header — for users, bots, groups, supergroups and channels alike. Tap the row to copy it; hold a group or channel id to copy the bot-API form (-100…) instead. The datacenter roughly tells you which region the account was registered in.",
                "Добавляет под шапкой профиля числовой ID и датацентр — для пользователей, ботов, групп, супергрупп и каналов одинаково. Нажатие копирует значение; удержание ID группы или канала копирует его в формате Bot API (-100…). Датацентр примерно показывает, в каком регионе был зарегистрирован аккаунт."
            ),
            rows: [
                .toggle(ClearToggle(L("Show ID", "Показывать ID"), .config(\.showProfileId))),
                .toggle(ClearToggle(L("Show Datacenter", "Показывать датацентр"), .config(\.showDC)))
            ]
        ),
        ClearSection(
            header: L("ACCOUNT ORIGIN", "ПРОИСХОЖДЕНИЕ АККАУНТА"),
            footer: L(
                "Registration month and the country the account's phone number belongs to. Telegram sends this only with the first message from someone who isn't your contact, so it's available when the client cached it back then — for everyone else the rows simply don't appear. Month precision; there is no exact date in the API.",
                "Месяц регистрации и страна, которой принадлежит номер аккаунта. Telegram присылает это только с первым сообщением от человека, которого нет у вас в контактах, поэтому данные есть лишь там, где клиент их тогда сохранил — у остальных строки просто не появятся. Точность — до месяца, точной даты в API нет."
            ),
            rows: [
                .toggle(ClearToggle(L("Show Registration Date", "Показывать дату регистрации"), .config(\.showRegistrationDate))),
                .toggle(ClearToggle(L("Show Phone Country", "Показывать страну номера"), .config(\.showPhoneCountry)))
            ]
        ),
        ClearSection(
            header: L("YOUR PROFILE", "ВАШ ПРОФИЛЬ"),
            footer: L(
                "Hides your phone number in Settings, so it isn't exposed when someone glances at your screen. It stays visible to whoever you already share it with. Requires a restart.",
                "Скрывает ваш номер телефона в настройках, чтобы он не попадался на глаза тому, кто заглянул в экран. Для тех, кому вы его уже показываете, номер остаётся видимым. Требуется перезапуск."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide My Phone Number", "Скрыть мой номер телефона"), .config(\.hidePhoneInSettings), requiresRestart: true))
            ]
        ),
        ClearSection(
            header: L("ACTIONS", "ДЕЙСТВИЯ"),
            footer: L(
                "Removes the call button from profiles, so you can't ring someone by mistake.",
                "Убирает кнопку звонка из профилей, чтобы нельзя было позвонить по ошибке."
            ),
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
            footer: L(
                "Asks before placing a call, so a misplaced tap doesn't ring someone.",
                "Спрашивает перед звонком, чтобы случайное нажатие никому не позвонило."
            ),
            rows: [
                .toggle(ClearToggle(L("Confirm Calls", "Подтверждать звонки"), .config(\.confirmCalls)))
            ]
        ),
        ClearSection(
            header: L("FACE ID / TOUCH ID", "FACE ID / TOUCH ID"),
            footer: L(
                "These actions run only after a successful check. If biometry is unavailable — locked out, denied or not enrolled — the device passcode is asked for instead; on a device with no passcode at all the action is blocked.",
                "Эти действия выполняются только после успешной проверки. Если биометрия недоступна — заблокирована, запрещена или не настроена — запрашивается код-пароль устройства; если и его нет, действие не выполняется."
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
                        "Planned: keep hidden chats out of contacts, recent calls, search and the share sheet too — not just the chat list.",
                        "В планах: убирать скрытые чаты не только из списка чатов, но и из контактов, недавних звонков, поиска и меню «Поделиться»."
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
                "Removes the summarize button on messages, the AI compose buttons in the input panels and the AI entry in the attachment menu.",
                "Убирает кнопку пересказа у сообщений, кнопки ИИ-набора в панелях ввода и пункт ИИ в меню вложений."
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
                        "Planned: strip the Premium upsell, Stars balance, gifts, boosts and collectibles out of the interface.",
                        "В планах: убрать из интерфейса рекламу Premium, баланс звёзд, подарки, бусты и коллекционные предметы."
                    )
                ))
            ]
        ),
        ClearSection(
            header: L("ADMIN", "АДМИНИСТРИРОВАНИЕ"),
            footer: L(
                "Hides the “N people want to join” banner admins see at the top of a channel. The requests themselves are untouched.",
                "Скрывает плашку «N человек хотят вступить», которую администраторы видят вверху канала. Сами заявки не затрагиваются."
            ),
            rows: [
                .toggle(ClearToggle(L("Hide Join Requests Banner", "Скрыть плашку заявок на вступление"), .config(\.hideChannelJoinRequests)))
            ]
        )
    ])
}
