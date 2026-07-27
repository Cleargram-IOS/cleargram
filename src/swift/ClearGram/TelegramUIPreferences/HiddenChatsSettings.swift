import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Selected peers hidden from chat list, recents panel, all search results. In-app and APNS
// notifications are suppressed; app badge subtracts hidden unread counts. Tapping a hidden
// peer is blocked at NavigateToChatController. Managed inside Settings -> Debug -> Peer Sync
// Preferences. Stored under shared-data key 31 (ApplicationSpecificSharedDataKeys.hiddenChatsSettings).

public struct HiddenChatsSettings: Codable, Equatable {
    public var hiddenPeerIds: [Int64]
    public var presets: [String: [Int64]]

    public static var defaultSettings: HiddenChatsSettings {
        return HiddenChatsSettings(hiddenPeerIds: [], presets: [:])
    }

    public init(hiddenPeerIds: [Int64] = [], presets: [String: [Int64]] = [:]) {
        self.hiddenPeerIds = hiddenPeerIds
        self.presets = presets
    }

    // Custom Codable: presets are packed into a flat [Int64] (count + ids per preset) to keep
    // the on-disk footprint small and the round-trip stable regardless of dictionary ordering.
    private enum CodingKeys: String, CodingKey {
        case hiddenPeerIds
        case presetNames
        case presetPeerIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hiddenPeerIds = try container.decodeIfPresent([Int64].self, forKey: .hiddenPeerIds) ?? []
        let names = try container.decodeIfPresent([String].self, forKey: .presetNames) ?? []
        // packed: [count0, id0_0, id0_1, ..., count1, id1_0, ...]
        let packed = try container.decodeIfPresent([Int64].self, forKey: .presetPeerIds) ?? []
        var p: [String: [Int64]] = [:]
        var idx = 0
        for name in names {
            guard idx < packed.count else { break }
            let count = Int(packed[idx]); idx += 1
            let ids = Array(packed[idx ..< min(idx + count, packed.count)])
            idx += count
            p[name] = ids
        }
        self.presets = p
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hiddenPeerIds, forKey: .hiddenPeerIds)
        let sorted = presets.sorted { $0.key < $1.key }
        try container.encode(sorted.map(\.key), forKey: .presetNames)
        var packed: [Int64] = []
        for (_, ids) in sorted { packed.append(Int64(ids.count)); packed.append(contentsOf: ids) }
        try container.encode(packed, forKey: .presetPeerIds)
    }

    public func isHidden(_ peerId: EnginePeer.Id) -> Bool {
        return hiddenPeerIds.contains(peerId.toInt64())
    }

    public func withToggled(_ peerId: EnginePeer.Id) -> HiddenChatsSettings {
        let id = peerId.toInt64()
        var ids = hiddenPeerIds
        if let idx = ids.firstIndex(of: id) {
            ids.remove(at: idx)
        } else {
            ids.append(id)
        }
        return HiddenChatsSettings(hiddenPeerIds: ids, presets: presets)
    }

    public func withPresetSaved(name: String) -> HiddenChatsSettings {
        var p = presets
        p[name] = hiddenPeerIds
        return HiddenChatsSettings(hiddenPeerIds: hiddenPeerIds, presets: p)
    }

    public func withPresetApplied(name: String) -> HiddenChatsSettings {
        return HiddenChatsSettings(hiddenPeerIds: presets[name] ?? hiddenPeerIds, presets: presets)
    }

    public func withPresetDeleted(name: String) -> HiddenChatsSettings {
        var p = presets
        p.removeValue(forKey: name)
        return HiddenChatsSettings(hiddenPeerIds: hiddenPeerIds, presets: p)
    }
}

public func updateHiddenChatsSettingsInteractively(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ f: @escaping (HiddenChatsSettings) -> HiddenChatsSettings
) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.hiddenChatsSettings, { entry in
            let current = entry?.get(HiddenChatsSettings.self) ?? HiddenChatsSettings.defaultSettings
            return SharedPreferencesEntry(f(current))
        })
    }
}
