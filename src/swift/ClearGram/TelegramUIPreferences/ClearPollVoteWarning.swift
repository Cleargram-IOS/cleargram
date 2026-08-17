import Foundation
import TelegramCore
import SwiftSignalKit

// Decides whether a poll vote deserves a confirmation alert, and which one.
//
// Two cases, in this order:
//
//  1. The poll cannot be revoted — either the creator disabled revoting (`revotingDisabled`,
//     the API flag behind "Allow changing the vote") or it is a quiz, where the answer is
//     final by construction. Telegram gives no hint of this before you tap, and the tap is
//     the point of no return, so warn *before* the first vote that the choice is permanent.
//     This is the case the feature was actually meant to cover.
//  2. The poll can be revoted and a different option is being picked, i.e. the vote is being
//     changed. That one is recoverable, so it is only a "are you sure" confirmation.
//
// A confirmed vote is re-dispatched through the same controller-interaction entry point, so
// the decision has to be suppressed exactly once for that message — `allowNextVote` records
// the permission and the next `textForPendingVote` consumes it. Recording it on confirmation
// (rather than when the alert is raised) is what keeps a cancelled alert from silently
// disarming the next attempt.
public enum ClearPollVoteWarning {
    private static let confirmedMessageIds = Atomic<Set<EngineMessage.Id>>(value: [])

    public static func allowNextVote(messageId: EngineMessage.Id) {
        let _ = confirmedMessageIds.modify { current -> Set<EngineMessage.Id> in
            var updated = current
            updated.insert(messageId)
            return updated
        }
    }

    public static func textForPendingVote(messageId: EngineMessage.Id, poll: TelegramMediaPoll, opaqueIdentifiers: [Data]) -> String? {
        var wasConfirmed = false
        let _ = confirmedMessageIds.modify { current -> Set<EngineMessage.Id> in
            var updated = current
            wasConfirmed = updated.remove(messageId) != nil
            return updated
        }
        if wasConfirmed {
            return nil
        }

        // An empty selection retracts the vote; nothing to warn about.
        guard !opaqueIdentifiers.isEmpty else {
            return nil
        }

        let currentlySelected = Set((poll.results.voters ?? []).filter({ $0.selected }).map({ $0.opaqueIdentifier }))
        if currentlySelected.isEmpty {
            return self.allowsRevoting(poll) ? nil : ClearStrings.confirmPollPermanentVote
        }
        if currentlySelected == Set(opaqueIdentifiers) {
            return nil
        }
        return ClearStrings.confirmPollRevote
    }

    private static func allowsRevoting(_ poll: TelegramMediaPoll) -> Bool {
        if poll.revotingDisabled {
            return false
        }
        // A quiz reveals the correct answer on the first tap — there is no going back from it,
        // regardless of the revoting flag.
        if case .quiz = poll.kind {
            return false
        }
        return true
    }
}
