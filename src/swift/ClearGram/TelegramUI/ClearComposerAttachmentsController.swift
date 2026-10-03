import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import LegacyComponents
import LegacyMediaPickerUI
import MediaPickerUI
import ChatTextInputPanelNode
import TelegramUIPreferences
import TextFormat

// The chat-controller half of feature__composer-attachments: what the input panel cannot do on its
// own because it needs the controller — opening the stock editor and camera, and sending.
extension ChatControllerImpl {
    func clearInstallComposerAttachments(panel: ChatTextInputPanelNode) {
        panel.clearComposer.openCamera = { [weak self] in
            self?.openCamera()
        }
        panel.clearComposer.openItem = { [weak self, weak panel] item, sourceView in
            guard let self, let panel else { return }
            self.clearOpenComposerItem(panel: panel, item: item, sourceView: sourceView)
        }
    }

    private func clearOpenComposerItem(panel: ChatTextInputPanelNode, item: TGMediaSelectableItem & TGMediaEditableItem, sourceView: UIView) {
        let attachments = panel.clearComposer.attachments
        // The editor's caption field starts from what is typed and hands its text back to the input
        // field when it closes or sends, so the two never disagree about the caption.
        attachments.editingContext.setForcedCaption(panel.inputTextState.inputText)
        let syncCaption: () -> Void = { [weak self, weak attachments] in
            guard let self, let attachments else { return }
            self.clearPickerRoutedToComposer(caption: clearCurrentCaption(attachments.editingContext))
        }
        self.chatDisplayNode.dismissInput()

        var isScheduledMessages = false
        if case .scheduledMessages = self.presentationInterfaceState.subject {
            isScheduledMessages = true
        }
        let peerId = self.chatLocation.peerId
        let hasTimer = peerId != self.context.account.peerId && peerId?.namespace == Namespaces.Peer.CloudUser

        let _ = clearPresentComposerItemEditor(
            context: self.context,
            peer: (self.presentationInterfaceState.renderedPeer?.peer).flatMap(EnginePeer.init),
            threadTitle: self.contentData?.state.threadInfo?.title,
            chatLocation: self.chatLocation,
            isScheduledMessages: isScheduledMessages,
            presentationData: self.presentationData,
            item: item,
            immediateThumbnail: (sourceView as? UIImageView)?.image,
            selectionContext: attachments.selectionContext,
            editingContext: attachments.editingContext,
            hasTimer: hasTimer,
            initialLayout: nil,
            transitionHostView: { [weak panel] in
                return panel?.view
            },
            transitionView: { [weak panel] identifier in
                return panel?.clearComposer.transitionView(for: identifier)
            },
            updateHiddenMedia: { [weak panel] identifier in
                panel?.clearComposer.setHiddenItem(id: identifier)
            },
            completed: { [weak self, weak panel] silently, scheduleTime, completion in
                // The editor's own send button sends everything attached with the caption it shows.
                // Passed straight in rather than through the input field, which may not have taken
                // the synced text yet within this same turn.
                guard let self, let panel else {
                    completion()
                    return
                }
                let caption = clearCurrentCaption(attachments.editingContext) ?? panel.inputTextState.inputText
                let cleaned = ClearURLCleaner.clean(text: expandedInputStateAttributedString(caption), strip: ClearConfig.stripTrackingParams, replace: ClearConfig.replacePreviewLinks)
                self.clearSendComposerAttachments(panel: panel, caption: cleaned, silentPosting: silently, scheduleTime: scheduleTime)
                completion()
            },
            presentSchedulePicker: { [weak self] _, done in
                self?.presentScheduleTimePicker(style: .media, completion: { result in
                    done(result.time, result.silentPosting)
                })
            },
            presentTimerPicker: { [weak self] done in
                self?.presentTimerPicker(style: .media, completion: { time in
                    done(time)
                })
            },
            getCaptionPanelView: { [weak self] in
                return self?.getCaptionPanelView(isFile: false)
            },
            present: { [weak self] c, a in
                self?.present(c, in: .window(.root), with: a, blockInteraction: true)
            },
            willTransitionOut: {
                syncCaption()
            }
        )
    }

    // The regular gallery picker runs on the input field's own contexts while the feature is on:
    // it opens with what is already attached ticked, everything picked or edited lands in the field
    // directly, and its plain send only closes it (`clearRouteToComposer`). Not for editing a
    // message's media, and not for the other picker modes.
    func clearComposerForPicker(subject: MediaPickerScreenImpl.Subject) -> ClearComposerAttachments? {
        guard ClearConfig.composerAttachments, case .assets(_, .default) = subject, self.presentationInterfaceState.interfaceState.editMessage == nil, let panel = self.chatDisplayNode.textInputPanelNode else {
            return nil
        }
        return panel.clearComposer.attachments
    }

    // What the picker's caption field held comes back as the input field's text — the picker was
    // seeded with that text, so this only differs when it was edited there.
    func clearPickerRoutedToComposer(caption: NSAttributedString?) {
        guard let caption, caption.string != self.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string else {
            return
        }
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            return state.updatedInterfaceState { interfaceState in
                return interfaceState.withUpdatedEffectiveInputState(ChatTextInputState(inputText: caption))
            }
        })
    }

    // Sends everything attached in one go, the text riding along as the caption — through the same
    // result signals and enqueue path the stock picker uses, so albums, edits, reply and paid
    // messages behave as they do there.
    func clearSendComposerAttachments(panel: ChatTextInputPanelNode, caption: NSAttributedString, silentPosting: Bool, scheduleTime: Int32?) {
        let attachments = panel.clearComposer.attachments
        attachments.editingContext.setForcedCaption(caption)
        let signals = TGMediaAssetsController.resultSignals(
            for: attachments.selectionContext,
            editingContext: attachments.editingContext,
            intent: TGMediaAssetsControllerSendMediaIntent,
            currentItem: nil,
            storeAssets: true,
            convertToJpeg: false,
            descriptionGenerator: legacyAssetPickerItemGenerator(),
            saveEditedPhotos: false
        )
        self.enqueueMediaMessages(signals: signals, silentPosting: silentPosting, scheduleTime: scheduleTime)
        self.clearInputText()
        attachments.clear()
    }
}
