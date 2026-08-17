import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Last.fm account state: the user's own API credentials, the session key returned by
// auth.getMobileSession, and the queue of scrobbles that couldn't be sent yet.
//
// Stored under shared-data key 33 (ApplicationSpecificSharedDataKeys.lastFmSettings) — NOT in
// ClearConfigSettings, deliberately: that struct is what the settings export writes into a
// `.cleargram` file the user may hand to someone else, and it is documented as holding nothing
// account-specific. A session key is a credential; it stays out of that file. Only the two
// on/off toggles (`lastFmScrobbling`, `lastFmNowPlaying`) live in ClearConfigSettings.
//
// The password is never stored — it is used once, for the sign-in call, and discarded.

public struct ClearLastFmScrobble: Equatable {
    public var artist: String
    public var track: String
    // Seconds; 0 when unknown.
    public var duration: Int32
    // UTC seconds at which the track started playing.
    public var timestamp: Int32

    public init(artist: String, track: String, duration: Int32, timestamp: Int32) {
        self.artist = artist
        self.track = track
        self.duration = duration
        self.timestamp = timestamp
    }

    // The queue is persisted as [String] rather than as an array of nested Codable structs —
    // shared-data entries round-trip through Postbox's adapted coder, and a flat list of strings
    // is the shape that is known to survive it. Unit separator, which cannot occur in a tag.
    private static let separator = "\u{1F}"

    var encoded: String {
        return [String(self.timestamp), String(self.duration), self.artist, self.track]
            .joined(separator: ClearLastFmScrobble.separator)
    }

    init?(encoded: String) {
        let fields = encoded.components(separatedBy: ClearLastFmScrobble.separator)
        guard fields.count == 4, let timestamp = Int32(fields[0]), let duration = Int32(fields[1]) else {
            return nil
        }
        guard !fields[2].isEmpty, !fields[3].isEmpty else {
            return nil
        }
        self.timestamp = timestamp
        self.duration = duration
        self.artist = fields[2]
        self.track = fields[3]
    }
}

public struct ClearLastFmSettings: Codable, Equatable {
    public var apiKey: String
    public var apiSecret: String
    public var sessionKey: String
    public var username: String
    // Scrobbles that failed to reach Last.fm, oldest first. See ClearLastFmSettings.maxPending.
    public var pendingRaw: [String]

    // Last.fm accepts at most 50 scrobbles per request; two batches is a sane ceiling for a
    // queue that only fills up while offline.
    public static let maxPending = 100

    public static var defaultSettings: ClearLastFmSettings {
        return ClearLastFmSettings(apiKey: "", apiSecret: "", sessionKey: "", username: "", pendingRaw: [])
    }

    public init(apiKey: String = "", apiSecret: String = "", sessionKey: String = "", username: String = "", pendingRaw: [String] = []) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.sessionKey = sessionKey
        self.username = username
        self.pendingRaw = pendingRaw
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey, apiSecret, sessionKey, username, pendingRaw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.apiSecret = try c.decodeIfPresent(String.self, forKey: .apiSecret) ?? ""
        self.sessionKey = try c.decodeIfPresent(String.self, forKey: .sessionKey) ?? ""
        self.username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.pendingRaw = try c.decodeIfPresent([String].self, forKey: .pendingRaw) ?? []
    }

    // Both halves of the API account are needed before anything can be signed.
    public var hasCredentials: Bool {
        return !self.apiKey.isEmpty && !self.apiSecret.isEmpty
    }

    public var isSignedIn: Bool {
        return self.hasCredentials && !self.sessionKey.isEmpty
    }

    public var pending: [ClearLastFmScrobble] {
        return self.pendingRaw.compactMap(ClearLastFmScrobble.init(encoded:))
    }

    public func withPending(_ scrobbles: [ClearLastFmScrobble]) -> ClearLastFmSettings {
        var updated = self
        updated.pendingRaw = scrobbles.suffix(ClearLastFmSettings.maxPending).map { $0.encoded }
        return updated
    }

    public func withSignedOut() -> ClearLastFmSettings {
        var updated = self
        updated.sessionKey = ""
        updated.username = ""
        return updated
    }
}

public func updateClearLastFmSettingsInteractively(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ f: @escaping (ClearLastFmSettings) -> ClearLastFmSettings
) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.lastFmSettings) { entry in
            let current = entry?.get(ClearLastFmSettings.self) ?? ClearLastFmSettings.defaultSettings
            return SharedPreferencesEntry(f(current))
        }
    }
}

public func clearLastFmSettingsEntry(
    accountManager: AccountManager<TelegramAccountManagerTypes>
) -> Signal<ClearLastFmSettings, NoError> {
    return accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.lastFmSettings])
    |> map { sharedData -> ClearLastFmSettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.lastFmSettings]?.get(ClearLastFmSettings.self) ?? ClearLastFmSettings.defaultSettings
    }
}
