import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import LegacyComponents

// Opens the stock full-screen media editor on one attachment from the input field
// (feature__composer-attachments). It is the same gallery the picker opens on a selected item —
// crop, drawing, filters, the lot — reading and writing the composer's own selection and editing
// contexts, so whatever is done here shows up on the thumbnail and goes out with the send.
// `presentLegacyMediaPickerGallery` is internal to this module, hence the wrapper.
public func clearPresentComposerItemEditor(
    context: AccountContext,
    peer: EnginePeer?,
    threadTitle: String?,
    chatLocation: ChatLocation?,
    isScheduledMessages: Bool,
    presentationData: PresentationData,
    item: TGMediaSelectableItem,
    immediateThumbnail: UIImage?,
    selectionContext: TGMediaSelectionContext,
    editingContext: TGMediaEditingContext,
    hasTimer: Bool,
    initialLayout: ContainerViewLayout?,
    transitionHostView: @escaping () -> UIView?,
    transitionView: @escaping (String) -> UIView?,
    updateHiddenMedia: @escaping (String?) -> Void,
    completed: @escaping (Bool, Int32?, @escaping () -> Void) -> Void,
    presentSchedulePicker: @escaping (Bool, @escaping (Int32, Bool) -> Void) -> Void,
    presentTimerPicker: @escaping (@escaping (Int32) -> Void) -> Void,
    getCaptionPanelView: @escaping () -> TGCaptionPanelView?,
    present: @escaping (ViewController, Any?) -> Void,
    willTransitionOut: @escaping () -> Void
) -> TGModernGalleryController {
    return presentLegacyMediaPickerGallery(
        context: context,
        peer: peer,
        threadTitle: threadTitle,
        chatLocation: chatLocation,
        isScheduledMessages: isScheduledMessages,
        presentationData: presentationData,
        source: .selection(item: item),
        immediateThumbnail: immediateThumbnail,
        selectionContext: selectionContext,
        editingContext: editingContext,
        asFile: false,
        hasSilentPosting: true,
        hasSchedule: !isScheduledMessages,
        hasTimer: hasTimer,
        updateHiddenMedia: updateHiddenMedia,
        initialLayout: initialLayout,
        transitionHostView: transitionHostView,
        transitionView: transitionView,
        completed: { _, silently, scheduleTime, completion in
            completed(silently, scheduleTime, completion)
        },
        presentSchedulePicker: presentSchedulePicker,
        presentTimerPicker: presentTimerPicker,
        getCaptionPanelView: getCaptionPanelView,
        present: present,
        finishedTransitionIn: {},
        willTransitionOut: willTransitionOut,
        dismissAll: {}
    )
}

// The caption as the picker's caption field holds it right now. `forcedCaption()` replays the
// current value on subscribe, so a synchronous read is just subscribe-and-dispose.
public func clearCurrentCaption(_ editingContext: TGMediaEditingContext) -> NSAttributedString? {
    var caption: NSAttributedString?
    let disposable = editingContext.forcedCaption()?.start(next: { next in
        caption = next as? NSAttributedString
    }, error: nil, completed: nil)
    disposable?.dispose()
    return caption
}
