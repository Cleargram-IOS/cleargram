import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Minimal Last.fm client — everything the scrobbler and the account screen need and nothing
// else: sign in (auth.getMobileSession), announce the current track (track.updateNowPlaying)
// and submit played tracks (track.scrobble).
//
// The API credentials are the user's own. Cleargram does not ship an api key: the repository is
// public, a key committed here would be a key handed to everyone, and Last.fm issues one per
// account in a few seconds at https://www.last.fm/api/account/create. That page hands out both
// halves — "API key" and "Shared secret" — and both are needed, because every write call is
// signed with the secret.
//
// Requests are plain URLSession over HTTPS, off Telegram's network stack entirely: this talks to
// Last.fm, not to Telegram, and has no business inside an MTProto connection.

public enum ClearLastFmError: Error {
    case notConfigured
    case network(String)
    // Last.fm's own error code and message. 9 = invalid session key (the user must sign in
    // again), 11/16 = the service is temporarily down and the scrobble is worth keeping.
    case api(code: Int, message: String)

    public var displayText: String {
        switch self {
        case .notConfigured:
            return ClearStrings.tr("Enter your Last.fm API key and shared secret first.", "Сначала укажите API-ключ и Shared secret Last.fm.")
        case let .network(text):
            return text
        case let .api(code, message):
            return "\(message) (\(code))"
        }
    }

    // A session that the server no longer accepts: keeping the queue is pointless until the
    // user signs in again.
    public var isAuthenticationFailure: Bool {
        if case let .api(code, _) = self {
            return code == 4 || code == 9 || code == 14
        }
        return false
    }
}

public enum ClearLastFm {
    // The page that hands out an API key and a shared secret. Shown in the settings footer and
    // on the account screen, because the feature cannot work without a visit there.
    public static let apiAccountUrl = "https://www.last.fm/api/account/create"

    private static let endpoint = "https://ws.audioscrobbler.com/2.0/"

    private static let cache = Atomic<ClearLastFmSettings>(value: ClearLastFmSettings.defaultSettings)
    private static let accountManagerRef = Atomic<AccountManager<TelegramAccountManagerTypes>?>(value: nil)
    private static let flushed = Atomic<Bool>(value: false)

    // Called from ClearConfig.start — same mirroring trick as ClearHooks/ClearStrings, so the
    // scrobbler can read credentials synchronously from any queue.
    public static func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        _ = accountManagerRef.swap(accountManager)
        _ = clearLastFmSettingsEntry(accountManager: accountManager).start(next: { value in
            _ = cache.swap(value)
            // One attempt per launch to drain whatever the last session couldn't send.
            if !value.pending.isEmpty && value.isSignedIn && !flushed.swap(true) {
                flushPending()
            }
        })
    }

    public static func current() -> ClearLastFmSettings {
        return cache.with { $0 }
    }

    public static func update(_ f: @escaping (ClearLastFmSettings) -> ClearLastFmSettings) {
        guard let accountManager = accountManagerRef.with({ $0 }) else {
            return
        }
        // Keep the in-memory copy ahead of the shared-data round trip: a scrobble that fails and
        // is immediately followed by another must not read a stale queue.
        _ = cache.modify { f($0) }
        _ = updateClearLastFmSettingsInteractively(accountManager: accountManager, f).start()
    }

    // MARK: - Signing

    // api_sig = md5(concat of key+value over params sorted by key, then the shared secret).
    // `format` is not part of the signature — Last.fm computes it over the call's own arguments.
    static func signature(_ params: [String: String], secret: String) -> String {
        var joined = ""
        for key in params.keys.sorted() {
            if key == "format" || key == "callback" {
                continue
            }
            joined += key
            joined += params[key] ?? ""
        }
        joined += secret
        guard let data = joined.data(using: .utf8) else {
            return ""
        }
        return EngineMemoryBuffer(data: data).md5Digest().map { String(format: "%02x", $0) }.joined()
    }

    private static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    // MARK: - Transport

    private static func post(
        _ params: [String: String],
        secret: String,
        completion: @escaping (Result<[String: Any], ClearLastFmError>) -> Void
    ) {
        var signed = params
        signed["api_sig"] = signature(params, secret: secret)
        signed["format"] = "json"

        guard let url = URL(string: endpoint) else {
            completion(.failure(.network("bad url")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(signed)
        request.timeoutInterval = 20.0

        URLSession.shared.dataTask(with: request) { data, _, error in
            Queue.mainQueue().async {
                if let error {
                    completion(.failure(.network(error.localizedDescription)))
                    return
                }
                guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.network(ClearStrings.tr("Unexpected reply from Last.fm.", "Неожиданный ответ от Last.fm."))))
                    return
                }
                if let code = object["error"] as? Int {
                    let message = object["message"] as? String ?? "error"
                    completion(.failure(.api(code: code, message: message)))
                    return
                }
                completion(.success(object))
            }
        }.resume()
    }

    // MARK: - Calls

    // Trades a username + password for a session key. The password is used here and nowhere
    // else — it is never written to shared data.
    public static func signIn(
        apiKey: String,
        apiSecret: String,
        username: String,
        password: String,
        completion: @escaping (Result<String, ClearLastFmError>) -> Void
    ) {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else {
            completion(.failure(.notConfigured))
            return
        }
        let params = [
            "method": "auth.getMobileSession",
            "username": username,
            "password": password,
            "api_key": apiKey
        ]
        post(params, secret: apiSecret) { result in
            switch result {
            case let .success(object):
                guard let session = object["session"] as? [String: Any],
                      let key = session["key"] as? String, !key.isEmpty else {
                    completion(.failure(.network(ClearStrings.tr("Unexpected reply from Last.fm.", "Неожиданный ответ от Last.fm."))))
                    return
                }
                let name = session["name"] as? String ?? username
                update { current in
                    var updated = current
                    updated.apiKey = apiKey
                    updated.apiSecret = apiSecret
                    updated.sessionKey = key
                    updated.username = name
                    return updated
                }
                completion(.success(name))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public static func signOut() {
        update { $0.withSignedOut() }
    }

    // "Now playing" is a transient status on the profile — it is not a scrobble and is never
    // queued: if it doesn't make it, there is nothing to retry.
    public static func updateNowPlaying(artist: String, track: String, duration: Int32) {
        let settings = current()
        guard settings.isSignedIn else {
            return
        }
        var params = [
            "method": "track.updateNowPlaying",
            "artist": artist,
            "track": track,
            "api_key": settings.apiKey,
            "sk": settings.sessionKey
        ]
        if duration > 0 {
            params["duration"] = String(duration)
        }
        post(params, secret: settings.apiSecret) { result in
            if case let .failure(error) = result {
                print("[cleargram/lastfm] now playing failed: \(error.displayText)")
                handleAuthenticationFailure(error)
            }
        }
    }

    // Submits the queued scrobbles together with `scrobble`, oldest first. Anything that doesn't
    // make it goes back into the queue, unless Last.fm rejected the session itself.
    public static func submit(_ scrobble: ClearLastFmScrobble?) {
        let settings = current()
        guard settings.isSignedIn else {
            return
        }
        var batch = settings.pending
        if let scrobble {
            batch.append(scrobble)
        }
        guard !batch.isEmpty else {
            return
        }
        // The API caps a request at 50 tracks; the rest stays queued for the next one.
        let sending = Array(batch.suffix(50))
        let keptBack = Array(batch.dropLast(sending.count))
        update { $0.withPending(keptBack) }

        var params = [
            "method": "track.scrobble",
            "api_key": settings.apiKey,
            "sk": settings.sessionKey
        ]
        for (index, item) in sending.enumerated() {
            params["artist[\(index)]"] = item.artist
            params["track[\(index)]"] = item.track
            params["timestamp[\(index)]"] = String(item.timestamp)
            if item.duration > 0 {
                params["duration[\(index)]"] = String(item.duration)
            }
        }
        post(params, secret: settings.apiSecret) { result in
            switch result {
            case .success:
                print("[cleargram/lastfm] scrobbled \(sending.count)")
            case let .failure(error):
                print("[cleargram/lastfm] scrobble failed: \(error.displayText)")
                if error.isAuthenticationFailure {
                    handleAuthenticationFailure(error)
                } else {
                    // Requeue in front of whatever arrived meanwhile, keeping time order.
                    update { current in
                        return current.withPending((sending + current.pending).sorted(by: { $0.timestamp < $1.timestamp }))
                    }
                }
            }
        }
    }

    public static func flushPending() {
        submit(nil)
    }

    public static func clearPending() {
        update { $0.withPending([]) }
    }

    // A rejected session key can never start working again on its own — drop it so the account
    // screen shows "signed out" instead of failing silently on every track.
    private static func handleAuthenticationFailure(_ error: ClearLastFmError) {
        guard error.isAuthenticationFailure else {
            return
        }
        print("[cleargram/lastfm] session rejected, signing out")
        update { $0.withSignedOut() }
    }
}
