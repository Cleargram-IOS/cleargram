import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

// Fork: an "Administrators" disclosure row on a group/channel profile, for members who are not
// admins themselves. Stock only shows the admins list to admins/owners (the row in
// PeerInfoProfileItems is gated behind `channel.adminRights != nil || .isCreator`), yet the API
// returns that list — channels.getParticipants with the channelParticipantsAdmins filter — to any
// member. Reading it here is the "read more than the official client shows" case, not a ToS bypass:
// no server-side visibility is defeated (a group with participants hidden simply returns nothing).
//
// The row reuses the stock plumbing wholesale: `openParticipantsSection(.admins)` pushes
// `channelAdminsController`, which degrades to a read-only list for a non-admin — every add /
// dismiss / edit control there is gated behind `hasPermission(.addAdmins)` / `.isCreator`, so a
// plain member sees only the names. Tapping an admin opens the stock `channelAdminController`,
// which is likewise read-only for a member (`canEditAdminRights` returns false), showing that
// admin's exact rights and rank.
//
// Gated by ClearConfig.showGroupAdmins (default-off, so the screen stays byte-for-byte stock) and
// suppressed when the account is an admin/creator — that path already has stock's own admins entry,
// and adding ours would duplicate it.

let clearItemGroupAdmins = 3008

func clearGroupAdminsItems(peer: EnginePeer?, context: AccountContext, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    guard ClearConfig.showGroupAdmins, let peer else {
        return []
    }

    switch peer {
    case let .channel(channel):
        if channel.adminRights != nil || channel.flags.contains(.isCreator) {
            return []
        }
    case let .legacyGroup(group):
        switch group.role {
        case .creator, .admin:
            return []
        case .member:
            break
        }
    default:
        return []
    }

    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
    return [PeerInfoScreenDisclosureItem(id: clearItemGroupAdmins, label: .none, text: strings.GroupInfo_Administrators, icon: PresentationResourcesSettings.admins, action: {
        interaction.openParticipantsSection(.admins)
    })]
}
