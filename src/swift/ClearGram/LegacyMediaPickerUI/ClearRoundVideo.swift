import Foundation
import UIKit
import Display
import LegacyComponents
import LegacyUI
import AccountContext
import SSignalKit
import SwiftSignalKit
import TelegramCore

// Round video messages ("кружки") are square, <= 60s, h264/mp4 with documentAttributeVideo
// roundMessage=true. Stock only ever produces them from VideoMessageCameraScreen; this turns a
// gallery video into one by reusing the conversion the share extension already performs
// (ShareItems.swift): a centred square crop plus the videoMessage quality preset, which
// FetchVideoMediaResource turns into an h264 export at upload time (400x400 / 1000 kbps, or
// whatever `roundVideoHighQuality` raises the preset to). No new
// encoder, no MediaEditorScreen.

public let clearRoundVideoMaxDuration: Double = 60.0
// Follows the recording side, so the declared attribute dimensions match what
// FetchVideoMediaResource actually exports once `roundVideoHighQuality` raises the preset.
public var clearRoundVideoSide: CGFloat {
    return CGFloat(clearRoundVideoRecordingSide())
}

public func clearRoundVideoAdjustments(originalSize: CGSize, existing: TGVideoEditAdjustments?) -> TGVideoEditAdjustments? {
    guard originalSize.width > 0.0, originalSize.height > 0.0 else {
        return existing
    }
    var cropRect = existing?.cropRect ?? CGRect(origin: CGPoint(), size: originalSize)
    if cropRect.isEmpty {
        cropRect = CGRect(origin: CGPoint(), size: originalSize)
    }
    let side = min(cropRect.width, cropRect.height)
    cropRect = CGRect(
        x: cropRect.minX + (cropRect.width - side) / 2.0,
        y: cropRect.minY + (cropRect.height - side) / 2.0,
        width: side,
        height: side
    )

    // Clamp the trim to 60s, mirroring -[TGVideoEditAdjustments editAdjustmentsWithPreset:maxDuration:]:
    // with a trim already applied, shorten the end; without one, cut at maxDuration outright.
    // (Done here rather than by calling that method — it has no usable Swift import.)
    let trimStart = existing?.trimStartValue ?? 0.0
    var trimEnd = existing?.trimEndValue ?? 0.0
    if trimStart > .ulpOfOne || trimEnd > .ulpOfOne {
        if trimEnd - trimStart > clearRoundVideoMaxDuration {
            trimEnd = trimStart + clearRoundVideoMaxDuration
        }
    } else {
        trimEnd = clearRoundVideoMaxDuration
    }

    return TGVideoEditAdjustments(
        originalSize: originalSize,
        cropRect: cropRect,
        cropOrientation: existing?.cropOrientation ?? .up,
        cropRotation: existing?.cropRotation ?? 0.0,
        cropLockedAspectRatio: 1.0,
        cropMirrored: existing?.cropMirrored ?? false,
        trimStartValue: trimStart,
        trimEndValue: trimEnd,
        toolValues: nil,
        paintingData: nil,
        sendAsGif: false,
        preset: TGMediaVideoConversionPresetVideoMessage
    )
}

// The declared preview dimensions must stay square or the circular placeholder is squashed.
public func clearSquareCroppedImage(_ image: UIImage) -> UIImage {
    let size = image.size
    if size.width <= 0.0 || size.height <= 0.0 || abs(size.width - size.height) < 1.0 {
        return image
    }
    let side = min(size.width, size.height)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    return renderer.image { _ in
        image.draw(at: CGPoint(x: -(size.width - side) / 2.0, y: -(size.height - side) / 2.0))
    }
}

// Whether this chat takes round video messages at all — the caller checks the feature toggle,
// this module has no TelegramUIPreferences dependency. Which *item* qualifies is decided by the
// gallery itself: it already knows which previewed item is a real video (the same test that
// governs the GIF button next to ours).
public func clearRoundVideoAllowed(peer: EnginePeer?) -> Bool {
    guard let peer else {
        return false
    }
    switch peer {
    case let .channel(channel):
        return channel.hasBannedPermission(.banSendInstantVideos) == nil
    case let .legacyGroup(group):
        return !group.hasBannedPermission(.banSendInstantVideos)
    default:
        return true
    }
}

// The gallery's buttons carry plain white glyphs on a dark circle, and there is no stock asset for
// "video message", so draw one: a ring — the кружок itself — around a play triangle.
public func clearRoundVideoButtonIcon() -> UIImage {
    let size = CGSize(width: 24.0, height: 24.0)
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        let c = context.cgContext
        c.setStrokeColor(UIColor.white.cgColor)
        c.setFillColor(UIColor.white.cgColor)
        c.setLineWidth(1.5)
        c.strokeEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: 1.75, dy: 1.75))

        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 9.5, y: 7.5))
        triangle.addLine(to: CGPoint(x: 17.0, y: 12.0))
        triangle.addLine(to: CGPoint(x: 9.5, y: 16.5))
        triangle.close()
        triangle.fill()
    }
}

// MARK: - Crop / trim editor

// Telegram already ships the exact UI a round video needs — it is the video-avatar editor:
// `TGPhotoEditorController` under `AvatarIntent` gives a circular crop mask, a draggable frame and
// a trimmer under the video, and it centres a square crop for us. The only thing that did not fit
// was its hardcoded 9.9s avatar trim limit, now the `clearMaximumVideoDuration` property.
//
// The result comes back through `didFinishEditingVideo` and is written into the picker's own
// editing context, so the ordinary send path runs afterwards: `legacyAssetPickerItemGenerator`
// reads the adjustments back out and `clearRoundVideoAdjustments` preserves the crop and trim.
public func clearPresentRoundVideoEditor(
    context: AccountContext,
    item: TGMediaEditableItem,
    editingContext: TGMediaEditingContext,
    present: @escaping (ViewController, Any?) -> Void,
    completed: @escaping () -> Void
) {
    // The editor MUST be given a real first frame. Its video scrubber builds placeholder
    // thumbnails via TGBlurredRectangularImage(_screenImage, ..., _screenImage.size, ...), which
    // with a nil image means a zero-sized bitmap context — that is what crashed on open. Stock's
    // avatar flow generates the frame first for exactly this reason, so do the same and only then
    // present.
    let presentEditor: (UIImage?) -> Void = { screenImage in
        clearPresentRoundVideoEditorWithScreenImage(context: context, item: item, editingContext: editingContext, screenImage: screenImage, present: present, completed: completed)
    }
    if let signal = item.screenImageSignal?(0.0) {
        var delivered = false
        signal.start(next: { next in
            guard !delivered else {
                return
            }
            delivered = true
            let image = next as? UIImage
            Queue.mainQueue().async {
                presentEditor(image)
            }
        })
    } else {
        presentEditor(nil)
    }
}

// Never hand the editor a nil frame — its scrubber would build a zero-sized bitmap context and
// crash. Only ever visible for the instant before real thumbnails load.
private func clearRoundVideoPlaceholderImage() -> UIImage {
    let size = CGSize(width: 32.0, height: 32.0)
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: CGPoint(), size: size))
    }
}

private func clearPresentRoundVideoEditorWithScreenImage(
    context: AccountContext,
    item: TGMediaEditableItem,
    editingContext: TGMediaEditingContext,
    screenImage: UIImage?,
    present: @escaping (ViewController, Any?) -> Void,
    completed: @escaping () -> Void
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let legacyController = LegacyController(presentation: .custom, theme: presentationData.theme, initialLayout: nil)
    legacyController.blocksBackgroundWhenInOverlay = true
    legacyController.acceptsFocusWhenInOverlay = true
    legacyController.statusBar.statusBarStyle = .Ignore
    legacyController.controllerLoaded = { [weak legacyController] in
        legacyController?.view.disablesInteractiveTransitionGestureRecognizer = true
    }

    guard let editorController = TGPhotoEditorController(
        context: legacyController.context,
        item: item,
        intent: TGPhotoEditorControllerAvatarIntent,
        adjustments: editingContext.adjustments(for: item),
        caption: nil,
        screenImage: screenImage ?? clearRoundVideoPlaceholderImage(),
        availableTabs: TGPhotoEditorController.defaultTabs(forAvatarIntent: false),
        selectedTab: TGPhotoEditorTab.cropTab
    ) else {
        return
    }
    editorController.clearMaximumVideoDuration = clearRoundVideoMaxDuration
    // No still frame is picked for a round video, so drop the avatar keyframe dot and its animation.
    editorController.clearHidesKeyframePicker = true
    editorController.editingContext = editingContext
    editorController.dontHideStatusBar = true
    editorController.skipInitialTransition = true

    editorController.requestThumbnailImage = { editableItem in
        return editableItem?.thumbnailImageSignal?()
    }
    editorController.requestOriginalScreenSizeImage = { editableItem, position in
        return editableItem?.screenImageSignal?(position)
    }
    editorController.requestOriginalFullSizeImage = { editableItem, position in
        guard let editableItem else {
            return nil
        }
        if editableItem.isVideo {
            if let asset = editableItem as? TGMediaAsset {
                return TGMediaAssetImageSignals.avAsset(forVideoAsset: asset, allowNetworkAccess: true)
            } else if let capturedVideo = editableItem as? TGCameraCapturedVideo {
                return capturedVideo.avAsset
            }
        }
        return editableItem.originalImageSignal?(position)
    }

    editorController.didFinishEditingVideo = { [weak legacyController] _, adjustments, _, _, _, commit in
        if let adjustments = adjustments as? TGVideoEditAdjustments {
            editingContext.setAdjustments(adjustments, for: item)
        }
        commit?()
        legacyController?.dismiss()
        completed()
    }
    editorController.onDismiss = { [weak legacyController] in
        legacyController?.dismiss()
    }

    legacyController.bind(controller: editorController)
    present(legacyController, nil)
}
