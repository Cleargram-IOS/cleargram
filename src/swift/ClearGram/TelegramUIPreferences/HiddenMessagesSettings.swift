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

    // Custom Codable, same reason as HiddenChatsSettings: a Dictionary cannot round-trip through
    // shared-data. Swift's synthesized `[String: T]` decoding calls `allKeys` on the keyed
    // container, and `AdaptedPostboxKeyedDecodingContainer.allKeys` is a `preconditionFailure()` —
    // so reading these settings traps (EXC_BREAKPOINT) instead of returning. Presets are therefore
    // packed into parallel arrays: names, plus [count, peerId, namespace, id, …] per preset.
    private enum CodingKeys: String, CodingKey {
        case enabled
        case hidden
        case presetNames
        case presetMessageIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.hidden = try container.decodeIfPresent([HiddenMessageId].self, forKey: .hidden) ?? []
        let names = try container.decodeIfPresent([String].self, forKey: .presetNames) ?? []
        let packed = try container.decodeIfPresent([Int64].self, forKey: .presetMessageIds) ?? []
        var p: [String: [HiddenMessageId]] = [:]
        var idx = 0
        for name in names {
            guard idx < packed.count else { break }
            let count = Int(packed[idx])
            idx += 1
            var ids: [HiddenMessageId] = []
            for _ in 0 ..< max(0, count) {
                guard idx + 2 < packed.count else { break }
                ids.append(HiddenMessageId(
                    peerId: packed[idx],
                    namespace: Int32(truncatingIfNeeded: packed[idx + 1]),
                    id: Int32(truncatingIfNeeded: packed[idx + 2])
                ))
                idx += 3
            }
            p[name] = ids
        }
        self.presets = p
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encode(self.hidden, forKey: .hidden)
        let sorted = self.presets.sorted { $0.key < $1.key }
        try container.encode(sorted.map(\.key), forKey: .presetNames)
        var packed: [Int64] = []
        for (_, ids) in sorted {
            packed.append(Int64(ids.count))
            for message in ids {
                packed.append(message.peerId)
                packed.append(Int64(message.namespace))
                packed.append(Int64(message.id))
            }
        }
        try container.encode(packed, forKey: .presetMessageIds)
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
