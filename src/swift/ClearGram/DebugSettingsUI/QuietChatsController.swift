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
import ItemListPeerItem

// Same shorthand as the settings screen: English source text first, Russian second.
private func L(_ en: String, _ ru: String) -> String {
    return ClearStrings.tr(en, ru)
}

private func hiddenMessagePreviewString(_ message: EngineMessage) -> String {
    if !message.text.isEmpty {
        return message.text
    }
    for media in message.media {
        if media is TelegramMediaImage {
            return L("Photo", "Фото")
        } else if media is TelegramMediaFile {
            return L("File", "Файл")
        }
    }
    return message.media.isEmpty ? L("Message", "Сообщение") : L("Media", "Медиа")
}

private enum QuietChatsSection: ItemListSectionId {
    case settings = 0
    case peers = 1
    case peerPresets = 2
    case messages = 3
    case messagePresets = 4
}

private enum QuietChatsEntry: ItemListNodeEntry {
    case toggle(PresentationTheme, String, Bool)
    case peersHeader(PresentationTheme, String)
    case peer(Int, EnginePeer, PresentationTheme, PresentationStrings)
    case addPeer(PresentationTheme, String)
    case peerPresetsHeader(PresentationTheme, String)
    case peerPreset(Int, String, PresentationTheme, PresentationStrings)
    case savePeerPreset(PresentationTheme, String)
    case messagesHeader(PresentationTheme, String)
    case message(Int, EnginePeer?, String, HiddenMessageId, PresentationTheme, PresentationStrings)
    case messagePresetsHeader(PresentationTheme, String)
    case messagePreset(Int, String, PresentationTheme, PresentationStrings)
    case saveMessagePreset(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .toggle: return QuietChatsSection.settings.rawValue
        case .peersHeader, .peer, .addPeer: return QuietChatsSection.peers.rawValue
        case .peerPresetsHeader, .peerPreset, .savePeerPreset: return QuietChatsSection.peerPresets.rawValue
        case .messagesHeader, .message: return QuietChatsSection.messages.rawValue
        case .messagePresetsHeader, .messagePreset, .saveMessagePreset: return QuietChatsSection.messagePresets.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .toggle: return 0
        case .peersHeader: return 100
        case let .peer(index, _, _, _): return 200 + index
        case .addPeer: return 9000
        case .peerPresetsHeader: return 10000
        case let .peerPreset(index, _, _, _): return 11000 + index
        case .savePeerPreset: return 19000
        case .messagesHeader: return 20000
        case let .message(index, _, _, _, _, _): return 21000 + index
        case .messagePresetsHeader: return 30000
        case let .messagePreset(index, _, _, _): return 31000 + index
        case .saveMessagePreset: return 39000
        }
    }

    static func < (lhs: QuietChatsEntry, rhs: QuietChatsEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: QuietChatsEntry, rhs: QuietChatsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.toggle(lt, ls, lv), .toggle(rt, rs, rv)): return lt === rt && ls == rs && lv == rv
        case let (.peersHeader(lt, ls), .peersHeader(rt, rs)): return lt === rt && ls == rs
        case let (.peer(li, lp, lt, _), .peer(ri, rp, rt, _)): return li == ri && lp == rp && lt === rt
        case let (.addPeer(lt, ls), .addPeer(rt, rs)): return lt === rt && ls == rs
        case let (.peerPresetsHeader(lt, ls), .peerPresetsHeader(rt, rs)): return lt === rt && ls == rs
        case let (.peerPreset(li, ln, lt, _), .peerPreset(ri, rn, rt, _)): return li == ri && ln == rn && lt === rt
        case let (.savePeerPreset(lt, ls), .savePeerPreset(rt, rs)): return lt === rt && ls == rs
        case let (.messagesHeader(lt, ls), .messagesHeader(rt, rs)): return lt === rt && ls == rs
        case let (.message(li, lp, ls, lid, lt, _), .message(ri, rp, rs, rid, rt, _)): return li == ri && lp == rp && ls == rs && lid == rid && lt === rt
        case let (.messagePresetsHeader(lt, ls), .messagePresetsHeader(rt, rs)): return lt === rt && ls == rs
        case let (.messagePreset(li, ln, lt, _), .messagePreset(ri, rn, rt, _)): return li == ri && ln == rn && lt === rt
        case let (.saveMessagePreset(lt, ls), .saveMessagePreset(rt, rs)): return lt === rt && ls == rs
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! QuietChatsArguments
        switch self {
        case let .toggle(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.toggleMessagesEnabled(value)
            })
        case let .peersHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .peer(_, peer, _, strings):
            return ItemListPeerItem(
                presentationData: presentationData,
                systemStyle: .glass,
                dateTimeFormat: PresentationDateTimeFormat(),
                nameDisplayOrder: .firstLast,
                context: args.context,
                peer: peer,
                presence: nil,
                text: .none,
                label: .none,
                editing: ItemListPeerItemEditing(editable: true, editing: true, revealed: false),
                revealOptions: ItemListPeerItemRevealOptions(options: [
                    ItemListPeerItemRevealOption(type: .destructive, title: strings.Common_Delete, action: { args.removePeer(peer.id) })
                ]),
                switchValue: nil,
                enabled: true,
                selectable: false,
                sectionId: self.section,
                action: nil,
                setPeerIdWithRevealedOptions: { _, _ in },
                removePeer: { _ in args.removePeer(peer.id) }
            )
        case let .addPeer(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.addPeer() })
        case let .peerPresetsHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .peerPreset(_, name, _, _):
            return ItemListCheckboxItem(presentationData: presentationData, title: name, style: .left, checked: false, zeroSeparatorInsets: false, sectionId: self.section, action: { args.applyPeerPreset(name) }, deleteAction: { args.deletePeerPreset(name) })
        case let .savePeerPreset(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.savePeerPreset() })
        case let .messagesHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .message(_, peer, preview, hiddenId, _, strings):
            if let peer = peer {
                return ItemListPeerItem(
                    presentationData: presentationData,
                    systemStyle: .glass,
                    dateTimeFormat: PresentationDateTimeFormat(),
                    nameDisplayOrder: .firstLast,
                    context: args.context,
                    peer: peer,
                    presence: nil,
                    text: .text(preview, .secondary),
                    label: .none,
                    editing: ItemListPeerItemEditing(editable: true, editing: true, revealed: false),
                    revealOptions: ItemListPeerItemRevealOptions(options: [
                        ItemListPeerItemRevealOption(type: .destructive, title: strings.Common_Delete, action: { args.removeMessage(hiddenId) })
                    ]),
                    switchValue: nil,
                    enabled: true,
                    selectable: false,
                    sectionId: self.section,
                    action: nil,
                    setPeerIdWithRevealedOptions: { _, _ in },
                    removePeer: { _ in args.removeMessage(hiddenId) }
                )
            } else {
                return ItemListCheckboxItem(presentationData: presentationData, title: preview, style: .left, checked: false, zeroSeparatorInsets: false, sectionId: self.section, action: {}, deleteAction: { args.removeMessage(hiddenId) })
            }
        case let .messagePresetsHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .messagePreset(_, name, _, _):
            return ItemListCheckboxItem(presentationData: presentationData, title: name, style: .left, checked: false, zeroSeparatorInsets: false, sectionId: self.section, action: { args.applyMessagePreset(name) }, deleteAction: { args.deleteMessagePreset(name) })
        case let .saveMessagePreset(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.saveMessagePreset() })
        }
    }
}

private struct QuietChatsArguments {
    let context: AccountContext
    let removePeer: (EnginePeer.Id) -> Void
    let addPeer: () -> Void
    let savePeerPreset: () -> Void
    let applyPeerPreset: (String) -> Void
    let deletePeerPreset: (String) -> Void
    let toggleMessagesEnabled: (Bool) -> Void
    let removeMessage: (HiddenMessageId) -> Void
    let saveMessagePreset: () -> Void
    let applyMessagePreset: (String) -> Void
    let deleteMessagePreset: (String) -> Void
}

public func quietChatsSelectionController(context: AccountContext) -> ViewController {
    var addPeerImpl: (() -> Void)?
    var savePeerPresetImpl: (() -> Void)?
    var saveMessagePresetImpl: (() -> Void)?

    let arguments = QuietChatsArguments(
        context: context,
        removePeer: { peerId in
            let _ = updateHiddenChatsSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withToggled(peerId) }.start()
        },
        addPeer: { addPeerImpl?() },
        savePeerPreset: { savePeerPresetImpl?() },
        applyPeerPreset: { name in
            let _ = updateHiddenChatsSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withPresetApplied(name: name) }.start()
        },
        deletePeerPreset: { name in
            let _ = updateHiddenChatsSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withPresetDeleted(name: name) }.start()
        },
        toggleMessagesEnabled: { value in
            let _ = updateHiddenMessagesSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withEnabled(value) }.start()
        },
        removeMessage: { hiddenId in
            let _ = updateHiddenMessagesSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withRemoved(hiddenId.engineId) }.start()
        },
        saveMessagePreset: { saveMessagePresetImpl?() },
        applyMessagePreset: { name in
            let _ = updateHiddenMessagesSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withPresetApplied(name: name) }.start()
        },
        deleteMessagePreset: { name in
            let _ = updateHiddenMessagesSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withPresetDeleted(name: name) }.start()
        }
    )

    let chatsSettingsSignal = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.hiddenChatsSettings])
    |> map { sharedData -> HiddenChatsSettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.hiddenChatsSettings]?.get(HiddenChatsSettings.self) ?? .defaultSettings
    }
    |> distinctUntilChanged

    let messagesSettingsSignal = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.hiddenMessagesSettings])
    |> map { sharedData -> HiddenMessagesSettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.hiddenMessagesSettings]?.get(HiddenMessagesSettings.self) ?? .defaultSettings
    }
    |> distinctUntilChanged

    let hiddenPeersSignal = chatsSettingsSignal
    |> map { $0.hiddenPeerIds.map { PeerId($0) } }
    |> distinctUntilChanged
    |> mapToSignal { peerIds -> Signal<[EnginePeer], NoError> in
        guard !peerIds.isEmpty else { return .single([]) }
        return context.engine.data.subscribe(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
        |> map { peers in peerIds.compactMap { peers[$0].flatMap { $0 } } }
    }

    let hiddenMessagesSignal = messagesSettingsSignal
    |> map { $0.hidden }
    |> distinctUntilChanged
    |> mapToSignal { hidden -> Signal<[(HiddenMessageId, EnginePeer?, String)], NoError> in
        guard !hidden.isEmpty else { return .single([]) }
        let messageIds = hidden.map { $0.engineId }
        return context.engine.data.subscribe(EngineDataMap(messageIds.map { TelegramEngine.EngineData.Item.Messages.Message(id: $0) }))
        |> map { messagesMap -> [(HiddenMessageId, EnginePeer?, String)] in
            return hidden.map { hiddenId -> (HiddenMessageId, EnginePeer?, String) in
                let engineId = hiddenId.engineId
                if let message = messagesMap[engineId].flatMap({ $0 }) {
                    let peer = message.peers[engineId.peerId].flatMap(EnginePeer.init)
                    return (hiddenId, peer, hiddenMessagePreviewString(message))
                } else {
                    return (hiddenId, nil, L("Message unavailable", "Сообщение недоступно"))
                }
            }
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, hiddenPeersSignal, chatsSettingsSignal, messagesSettingsSignal, hiddenMessagesSignal)
    |> map { presentationData, peers, chatsSettings, messagesSettings, messagesContent -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let pd = ItemListPresentationData(presentationData)
        var entries: [QuietChatsEntry] = []

        entries.append(.toggle(presentationData.theme, L("Show Hide Option in Messages", "Показывать «Скрыть» в сообщениях"), messagesSettings.enabled))

        entries.append(.peersHeader(presentationData.theme, L("HIDDEN CHATS", "СКРЫТЫЕ ЧАТЫ")))
        for (i, peer) in peers.enumerated() {
            entries.append(.peer(i, peer, presentationData.theme, presentationData.strings))
        }
        entries.append(.addPeer(presentationData.theme, L("Add Chat", "Добавить чат")))

        entries.append(.peerPresetsHeader(presentationData.theme, L("CHAT PRESETS", "НАБОРЫ ЧАТОВ")))
        let sortedChatPresets = chatsSettings.presets.keys.sorted()
        for (i, name) in sortedChatPresets.enumerated() {
            entries.append(.peerPreset(i, name, presentationData.theme, presentationData.strings))
        }
        entries.append(.savePeerPreset(presentationData.theme, L("Save Current Chats as Preset", "Сохранить текущие чаты как набор")))

        entries.append(.messagesHeader(presentationData.theme, L("HIDDEN MESSAGES", "СКРЫТЫЕ СООБЩЕНИЯ")))
        for (i, item) in messagesContent.enumerated() {
            entries.append(.message(i, item.1, item.2, item.0, presentationData.theme, presentationData.strings))
        }

        entries.append(.messagePresetsHeader(presentationData.theme, L("MESSAGE PRESETS", "НАБОРЫ СООБЩЕНИЙ")))
        let sortedMessagePresets = messagesSettings.presets.keys.sorted()
        for (i, name) in sortedMessagePresets.enumerated() {
            entries.append(.messagePreset(i, name, presentationData.theme, presentationData.strings))
        }
        entries.append(.saveMessagePreset(presentationData.theme, L("Save Current Messages as Preset", "Сохранить текущие сообщения как набор")))

        let state = ItemListControllerState(presentationData: pd, title: .text(L("Peer Sync Preferences", "Скрытые чаты и сообщения")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: pd, entries: entries, style: .blocks, animateChanges: true), arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    addPeerImpl = { [weak controller] in
        guard let controller else { return }
        let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
            context: context,
            filter: [.onlyWriteable, .excludeDisabled],
            hasChatListSelector: true,
            hasContactSelector: false,
            hasGlobalSearch: false,
            title: L("Select Chat", "Выберите чат")
        ))
        selector.peerSelected = { [weak selector] peer, _ in
            let _ = updateHiddenChatsSettingsInteractively(accountManager: context.sharedContext.accountManager) { settings in
                guard !settings.isHidden(peer.id) else { return settings }
                return settings.withToggled(peer.id)
            }.start()
            selector?.dismiss()
        }
        controller.push(selector)
    }

    savePeerPresetImpl = { [weak controller] in
        guard let controller else { return }
        let alert = UIAlertController(
            title: L("Save Chat Preset", "Сохранить набор чатов"),
            message: L("Enter a name for this preset", "Введите название набора"),
            preferredStyle: .alert
        )
        alert.addTextField { tf in tf.placeholder = L("Preset name", "Название набора") }
        alert.addAction(UIAlertAction(title: L("Save", "Сохранить"), style: .default) { _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            let _ = updateHiddenChatsSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withPresetSaved(name: name) }.start()
        })
        alert.addAction(UIAlertAction(title: L("Cancel", "Отмена"), style: .cancel))
        controller.present(alert, animated: true)
    }

    saveMessagePresetImpl = { [weak controller] in
        guard let controller else { return }
        let alert = UIAlertController(
            title: L("Save Message Preset", "Сохранить набор сообщений"),
            message: L("Enter a name for this preset", "Введите название набора"),
            preferredStyle: .alert
        )
        alert.addTextField { tf in tf.placeholder = L("Preset name", "Название набора") }
        alert.addAction(UIAlertAction(title: L("Save", "Сохранить"), style: .default) { _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            let _ = updateHiddenMessagesSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withPresetSaved(name: name) }.start()
        })
        alert.addAction(UIAlertAction(title: L("Cancel", "Отмена"), style: .cancel))
        controller.present(alert, animated: true)
    }

    return controller
}
