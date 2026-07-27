import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Local per-message hide. Filtered from chat history, in-chat and global search, and
// shared-media panes — without deleting from the server. Gated by an `enabled` flag,
// managed inside Peer Sync Preferences. Stored under shared-data key 32.

public struct HiddenMessageId: Codable, Equatable, Hashable {
    public var peerId: Int64
    public var namespace: Int32
    public var id: Int32

    public init(peerId: Int64, namespace: Int32, id: Int32) {
        self.peerId = peerId
        self.namespace = namespace
        self.id = id
    }

    public init(_ messageId: EngineMessage.Id) {
        self.peerId = messageId.peerId.toInt64()
        self.namespace = messageId.namespace
        self.id = messageId.id
    }

    public var engineId: EngineMessage.Id {
        return EngineMessage.Id(
            peerId: EnginePeer.Id(self.peerId),
            namespace: self.namespace,
            id: self.id
        )
    }
}

public struct HiddenMessagesSettings: Codable, Equatable {
    public var enabled: Bool
    public var hidden: [HiddenMessageId]
    public var presets: [String: [HiddenMessageId]]

    public static var defaultSettings: HiddenMessagesSettings {
        return HiddenMessagesSettings(enabled: false, hidden: [], presets: [:])
    }

    public init(enabled: Bool = false, hidden: [HiddenMessageId] = [], presets: [String: [HiddenMessageId]] = [:]) {
        self.enabled = enabled
        self.hidden = hidden
        self.presets = presets
    }

    // Accessors used by the chat-history filter and the management UI.
    public var hiddenMessageIds: [EngineMessage.Id] {
        return self.hidden.map { $0.engineId }
    }

    public var hiddenMessageIdSet: Set<EngineMessage.Id> {
        return Set(self.hidden.map { $0.engineId })
    }

    public func isHidden(_ messageId: EngineMessage.Id) -> Bool {
        return hiddenMessageIdSet.contains(messageId)
    }

    public func withToggled(_ messageId: EngineMessage.Id) -> HiddenMessagesSettings {
        let target = HiddenMessageId(messageId)
        var hidden = self.hidden
        if let idx = hidden.firstIndex(of: target) {
            hidden.remove(at: idx)
        } else {
            hidden.append(target)
        }
        return HiddenMessagesSettings(enabled: enabled, hidden: hidden, presets: presets)
    }

    public func withAdded(_ messageIds: [EngineMessage.Id]) -> HiddenMessagesSettings {
        var hidden = self.hidden
        for messageId in messageIds {
            let target = HiddenMessageId(messageId)
            if !hidden.contains(target) {
                hidden.append(target)
            }
        }
        return HiddenMessagesSettings(enabled: self.enabled, hidden: hidden, presets: self.presets)
    }

    public func withRemoved(_ messageId: EngineMessage.Id) -> HiddenMessagesSettings {
        var hidden = self.hidden
        if let index = hidden.firstIndex(of: HiddenMessageId(messageId)) {
            hidden.remove(at: index)
        }
        return HiddenMessagesSettings(enabled: self.enabled, hidden: hidden, presets: self.presets)
    }

    public func withEnabled(_ enabled: Bool) -> HiddenMessagesSettings {
        return HiddenMessagesSettings(enabled: enabled, hidden: self.hidden, presets: self.presets)
    }

    public func withPresetSaved(name: String) -> HiddenMessagesSettings {
        var presets = self.presets
        presets[name] = self.hidden
        return HiddenMessagesSettings(enabled: self.enabled, hidden: self.hidden, presets: presets)
    }

    public func withPresetApplied(name: String) -> HiddenMessagesSettings {
        return HiddenMessagesSettings(enabled: self.enabled, hidden: self.presets[name] ?? self.hidden, presets: self.presets)
    }

    public func withPresetDeleted(name: String) -> HiddenMessagesSettings {
        var presets = self.presets
        presets.removeValue(forKey: name)
        return HiddenMessagesSettings(enabled: self.enabled, hidden: self.hidden, presets: presets)
    }
}

public func updateHiddenMessagesSettingsInteractively(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ f: @escaping (HiddenMessagesSettings) -> HiddenMessagesSettings
) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.hiddenMessagesSettings) { entry in
            let current = entry?.get(HiddenMessagesSettings.self) ?? HiddenMessagesSettings.defaultSettings
            return SharedPreferencesEntry(f(current))
        }
    }
}

public func hiddenMessagesSettingsEntry(
    accountManager: AccountManager<TelegramAccountManagerTypes>
) -> Signal<HiddenMessagesSettings, NoError> {
    return accountManager.sharedData(
        keys: [ApplicationSpecificSharedDataKeys.hiddenMessagesSettings]
    )
    |> map { sharedData -> HiddenMessagesSettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.hiddenMessagesSettings]?.get(HiddenMessagesSettings.self) ?? HiddenMessagesSettings.defaultSettings
    }
}
