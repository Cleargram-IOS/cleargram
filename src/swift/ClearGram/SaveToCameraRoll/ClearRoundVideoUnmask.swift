import Foundation
import UIKit
import AVFoundation
import CoreImage
import Photos
import SwiftSignalKit
import TelegramCore
import DeviceAccess
import AccountContext

// Saving a round video message ("кружок") with everything outside the visible circle removed.
//
// A кружок is an ordinary square mp4; the circle is drawn by the *receiving* client, which masks
// whatever arrives by the `instantRoundVideo` flag. So the corners of the file are pixels nobody
// has ever seen, and the sender is free to put anything there. Telegram puts branding: stock iOS
// composites a flat white plate (CameraRoundLegacyVideoFilter), newer builds a darkened blurred
// backdrop plus a wordmark and an animated plane logo (CameraRoundVideoFilter), and other
// platforms do their own third thing. Save the file as-is and that is what lands in Photos.
//
// The one invariant that holds across every client and version is the geometry: what was visible
// is exactly the circle inscribed in the frame. So there is nothing to detect and nothing to
// special-case — read the real dimensions off the track, centre a square, blank everything
// outside the inscribed circle. Nothing that any viewer ever saw is lost.
//
// The cost is a re-encode: four corners cannot be removed by a rectangular crop without cutting
// into the circle, so `AVAssetExportPresetPassthrough` is not an option. The export runs at the
// source resolution with a generous preset, which keeps the second generation close to lossless.

public func clearSaveRoundVideoUnmasked(
    context: AccountContext,
    userLocation: MediaResourceUserLocation,
    mediaReference: AnyMediaReference
) -> Signal<Float, NoError> {
    return fetchMediaData(context: context, userLocation: userLocation, mediaReference: mediaReference)
    |> mapToSignal { state, _ -> Signal<Float, NoError> in
        switch state {
        case let .progress(value):
            // The download is the first half of the bar, the export the second.
            return .single(value * 0.5)
        case let .data(data):
            guard data.isComplete else {
                return .complete()
            }
            return clearExportAndSaveUnmasked(context: context, sourcePath: data.path)
            |> map { 0.5 + $0 * 0.5 }
        }
    }
}

private func clearExportAndSaveUnmasked(context: AccountContext, sourcePath: String) -> Signal<Float, NoError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: presentationData, present: { c, a in
            context.sharedContext.presentGlobalController(c, a)
        }, openSettings: context.sharedContext.applicationBindings.openSettings, { authorized in
            guard authorized else {
                subscriber.putCompletion()
                return
            }

            // AVAsset infers the container from the path extension, and a resource path in the
            // media box has none unless the sender happened to set a file name. Copy first.
            let inputPath = NSTemporaryDirectory() + "\(Int64.random(in: Int64.min ... Int64.max)).mp4"
            let outputPath = NSTemporaryDirectory() + "\(Int64.random(in: Int64.min ... Int64.max)).mp4"
            guard let _ = try? FileManager.default.copyItem(atPath: sourcePath, toPath: inputPath) else {
                subscriber.putCompletion()
                return
            }

            let cleanUp: () -> Void = {
                let _ = try? FileManager.default.removeItem(atPath: inputPath)
                let _ = try? FileManager.default.removeItem(atPath: outputPath)
            }

            guard let session = clearRoundVideoUnmaskExportSession(
                inputURL: URL(fileURLWithPath: inputPath),
                outputURL: URL(fileURLWithPath: outputPath)
            ) else {
                cleanUp()
                subscriber.putCompletion()
                return
            }

            let progressTimer = SwiftSignalKit.Timer(timeout: 0.15, repeat: true, completion: { [weak session] in
                guard let session else {
                    return
                }
                subscriber.putNext(session.progress)
            }, queue: Queue.mainQueue())
            progressTimer.start()

            session.exportAsynchronously {
                Queue.mainQueue().async {
                    progressTimer.invalidate()
                    guard session.status == .completed else {
                        print("ClearGram: round video unmask export failed — \(String(describing: session.error))")
                        cleanUp()
                        subscriber.putCompletion()
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: outputPath))
                    }, completionHandler: { _, error in
                        if let error {
                            print("ClearGram: round video unmask save failed — \(error)")
                        }
                        cleanUp()
                        subscriber.putNext(1.0)
                        subscriber.putCompletion()
                    })
                }
            }

            disposable.set(ActionDisposable {
                progressTimer.invalidate()
                session.cancelExport()
            })
        })
        return disposable
    }
    |> runOn(Queue.mainQueue())
}

private func clearRoundVideoUnmaskExportSession(inputURL: URL, outputURL: URL) -> AVAssetExportSession? {
    let asset = AVURLAsset(url: inputURL)
    guard let track = asset.tracks(withMediaType: .video).first else {
        return nil
    }

    // A centred square crop and a circular mask are both invariant under the 90° rotations and
    // mirroring a track's `preferredTransform` can carry, and `min` of the natural size survives
    // a rotation swapping width for height. So the side can be settled up front without ever
    // touching the transform — which is deliberate: the composition built by
    // `applyingCIFiltersWithHandler` already delivers oriented frames, and applying the
    // transform a second time here would tip the кружок onto its side.
    let side = min(track.naturalSize.width, track.naturalSize.height)
    guard side > 0.0 else {
        return nil
    }

    let squareSize = CGSize(width: side, height: side)
    let circleMask = CIImage(image: clearCircleMaskImage(side: side))
    let background = CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: squareSize))

    let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
        // Measured off the frame that actually arrived rather than off the track, so a source
        // whose frames disagree with `naturalSize` still gets a centred crop.
        let extent = request.sourceImage.extent
        let sourceSide = min(extent.width, extent.height)
        let dx = extent.origin.x + (extent.width - sourceSide) / 2.0
        let dy = extent.origin.y + (extent.height - sourceSide) / 2.0
        var image = request.sourceImage
            .cropped(to: CGRect(x: dx, y: dy, width: sourceSide, height: sourceSide))
            .transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
        if sourceSide > 0.0, abs(sourceSide - side) > 0.5 {
            let scale = side / sourceSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let circleMask else {
            request.finish(with: image, context: nil)
            return
        }
        request.finish(with: image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: circleMask
        ]), context: nil)
    })
    composition.renderSize = squareSize

    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
        return nil
    }
    session.videoComposition = composition
    session.outputURL = outputURL
    session.outputFileType = .mp4
    return session
}

// White inside the circle, black outside — the mask CIBlendWithMask blends against. Drawn a
// fraction wide so the export's own resampling cannot leave a rim of background colour.
private func clearCircleMaskImage(side: CGFloat) -> UIImage {
    let size = CGSize(width: side, height: side)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor.white.setFill()
        context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: -1.0, dy: -1.0))
    }
}
