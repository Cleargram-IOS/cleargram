import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ContextUI
import UndoUI

// Fork: numeric peer id + datacenter rows, shared by every branch of `infoItems`
// (user / bot / channel / supergroup / legacy group). Gated by ClearConfig.showProfileId and
// ClearConfig.showDC — both default-off, so with the toggles off nothing is appended and the
// screen is byte-for-byte stock.
//
// The id shown is the raw MTProto id, which is what Postbox stores (see ApiGroupOrChannel.swift:
// `PeerId(namespace: Namespaces.Peer.CloudChannel, id: .._internalFromInt64Value(id))` — no -100
// prefix anywhere in the codebase). The bot-API form is offered as a second long-press action,
// since that is the one you paste into a bot.

let clearItemPeerId = 3006
let clearItemPeerDc = 3007

func clearBotApiPeerId(_ peer: EnginePeer) -> String? {
    let raw = peer.id.id._internalGetInt64Value()
    switch peer {
    case .channel:
        return "-100\(raw)"
    case .legacyGroup:
        return "-\(raw)"
    default:
        return nil
    }
}

private func clearCopyValue(_ value: String, context: AccountContext, interaction: PeerInfoInteraction) {
    UIPasteboard.general.string = value
    if let controller = interaction.getController() {
        let pd = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: pd, content: .copy(text: pd.strings.Conversation_TextCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
    }
}

private func clearCopyableRow(
    id: Int,
    label: String,
    text: String,
    copyValue: String,
    extraCopy: (title: String, value: String)?,
    context: AccountContext,
    interaction: PeerInfoInteraction
) -> PeerInfoScreenLabeledValueItem {
    return PeerInfoScreenLabeledValueItem(id: id, label: label, text: text, textColor: .primary, action: { _, _ in
        clearCopyValue(copyValue, context: context, interaction: interaction)
        interaction.requestLayout(false)
    }, longTapAction: nil, contextAction: { node, gesture, _ in
        guard let sourceNode = node as? ContextExtractedContentContainingNode, let gesture = gesture else {
            clearCopyValue(copyValue, context: context, interaction: interaction)
            interaction.requestLayout(false)
            return
        }
        let pd = context.sharedContext.currentPresentationData.with { $0 }
        let copyIcon: (PresentationTheme) -> UIImage? = { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
        }
        var menuItems: [ContextMenuItem] = []
        menuItems.append(.action(ContextMenuActionItem(text: pd.strings.Conversation_ContextMenuCopy, icon: copyIcon, action: { c, _ in
            c?.dismiss { clearCopyValue(copyValue, context: context, interaction: interaction) }
        })))
        if let extraCopy {
            menuItems.append(.action(ContextMenuActionItem(text: extraCopy.title, icon: copyIcon, action: { c, _ in
                c?.dismiss { clearCopyValue(extraCopy.value, context: context, interaction: interaction) }
            })))
        }
        let contextController = makeContextController(presentationData: pd, source: .extracted(PeerInfoContextExtractedContentSource(sourceNode: sourceNode)), items: .single(ContextController.Items(content: .list(menuItems))), gesture: gesture)
        interaction.getController()?.present(contextController, in: .window(.root))
    }, requestLayout: { animated in
        interaction.requestLayout(animated)
    })
}

func clearPeerIdItems(peer: EnginePeer?, context: AccountContext, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    guard let peer else {
        return []
    }
    var result: [PeerInfoScreenItem] = []

    if ClearConfig.showProfileId {
        let idText = "\(peer.id.id._internalGetInt64Value())"
        var extraCopy: (title: String, value: String)?
        if let botApi = clearBotApiPeerId(peer) {
            extraCopy = (title: "Copy Bot API ID", value: botApi)
        }
        result.append(clearCopyableRow(id: clearItemPeerId, label: "id", text: idText, copyValue: idText, extraCopy: extraCopy, context: context, interaction: interaction))
    }

    if ClearConfig.showDC, let representation = peer.profileImageRepresentations.first, let cloudResource = representation.resource as? CloudPeerPhotoSizeMediaResource {
        let dcId = cloudResource.datacenterId
        result.append(clearCopyableRow(id: clearItemPeerDc, label: "dc", text: "DC \(dcId)", copyValue: "\(dcId)", extraCopy: nil, context: context, interaction: interaction))
    }

    return result
}
