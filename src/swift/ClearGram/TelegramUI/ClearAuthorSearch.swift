import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import SearchPeerMembers
import TelegramUIPreferences

// Author suggestions for in-chat search when the group hides its member list.
//
// Stock builds that list from `searchPeerMembers(... scope: .memberSuggestion)`, which asks the
// server for participants — so in a group with participants hidden it comes back empty and there
// is no way to pick an author at all. The search itself is not the problem: `messages.search` with
// `from_id` works fine in those groups, which is exactly what stock's own "search from this user"
// long-press action relies on.
//
// The real constraint is in `SearchMessages.swift`:
//
//     if let value = transaction.getPeer(fromId).flatMap(apiInputPeer) { ... }
//
// The author has to be in the local store with an access hash. That is why the long-press path
// works — the user posted, so the peer arrived cached alongside the message — and it is why a bare
// user id typed by hand cannot work: an `InputPeer` needs an access hash that nothing local holds.
// **And that failure is silent**: with no peer, `fromId` is dropped and the request goes out with
// no author filter, returning the entire chat rather than nothing. So this never hands back a peer
// it could not actually resolve; a suggestion that appears here is one the search can really use.
//
// Two sources are added on top of stock, both of which do produce a usable peer:
//
//   - a username, resolved through `resolvePeerByName` — this is the case that unlocks hidden
//     member lists, because resolution does not care about membership and caches the access hash;
//   - a numeric id, looked up in the local store only, for a peer already known from somewhere
//     else in the app. No network: the server offers no id→peer lookup, so if it is not cached
//     there is nothing honest to return.

private let clearUsernameAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

private func clearNormalizedUsername(_ query: String) -> String? {
    var value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("@") {
        value.removeFirst()
    }
    guard value.count >= 4, value.count <= 32 else {
        return nil
    }
    guard value.unicodeScalars.allSatisfy({ clearUsernameAllowed.contains($0) }) else {
        return nil
    }
    // An all-digit string is an id, not a username — Telegram does not allow those as usernames.
    guard value.contains(where: { !$0.isNumber }) else {
        return nil
    }
    return value
}

private func clearNumericPeerId(_ query: String) -> EnginePeer.Id? {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.allSatisfy({ $0.isNumber }), let raw = Int64(value) else {
        return nil
    }
    return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(raw))
}

/// Stock member suggestions, plus a username or a locally known id when the member list is hidden.
/// Returns the stock result untouched while the toggle is off.
public func clearSearchAuthorSuggestions(
    context: AccountContext,
    peerId: EnginePeer.Id,
    chatLocation: ChatLocation,
    query: String
) -> Signal<[EnginePeer], NoError> {
    let stock = searchPeerMembers(context: context, peerId: peerId, chatLocation: chatLocation, query: query, scope: .memberSuggestion)
    guard ClearConfig.searchHiddenMembers else {
        return stock
    }

    let extra: Signal<[EnginePeer], NoError>
    if let username = clearNormalizedUsername(query) {
        extra = context.engine.peers.resolvePeerByName(name: username, referrer: nil)
        |> mapToSignal { result -> Signal<[EnginePeer], NoError> in
            switch result {
            case .progress:
                // Nothing to show yet; the stock list still renders while this settles.
                return .complete()
            case let .result(peer):
                guard let peer, case .user = peer else {
                    return .single([])
                }
                return .single([peer])
            }
        }
    } else if let id = clearNumericPeerId(query) {
        extra = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: id))
        |> map { peer -> [EnginePeer] in
            guard let peer, case .user = peer else {
                return []
            }
            return [peer]
        }
    } else {
        extra = .single([])
    }

    return combineLatest(stock, extra)
    |> map { stockPeers, extraPeers -> [EnginePeer] in
        guard !extraPeers.isEmpty else {
            return stockPeers
        }
        var seen = Set(stockPeers.map { $0.id })
        var result = stockPeers
        for peer in extraPeers where !seen.contains(peer.id) {
            seen.insert(peer.id)
            result.append(peer)
        }
        return result
    }
}
