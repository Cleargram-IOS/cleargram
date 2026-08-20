import Foundation
import UIKit
import Display
import DebugSettingsUI

// Cleargram: the equalizer's only entry point — a button in the fullscreen music player, sitting
// across the scrubber from the playback-rate button.
//
// The rate button's context menu would have been the tidier home, but stock only shows that button
// when `SharedMediaPlaybackDisplayData.music` comes back with `long` set, and `long` is
// `duration > 10 minutes` — so for an ordinary song there is no menu to hang anything off.
//
// Lives in TelegramUI because it needs both ends: `OverlayAudioPlayerControllerImpl`, for the
// account context and the navigation controller the player was pushed onto (the controls node
// holds an account and an engine, but no context), and `DebugSettingsUI` for the screen itself.

// Three faders at different heights. Drawn rather than shipped as an asset: there is no
// equalizer glyph in the bundle, and this is one shape at one size.
func clearEqualizerButtonIcon(color: UIColor) -> UIImage? {
    return generateImage(CGSize(width: 24.0, height: 24.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))

        let centers: [CGFloat] = [5.0, 12.0, 19.0]
        // Where each fader's cap sits along its track, top to bottom.
        let positions: [CGFloat] = [9.0, 15.0, 11.0]
        let trackWidth: CGFloat = 1.5
        let capSize = CGSize(width: 6.0, height: 2.5)

        for (index, center) in centers.enumerated() {
            context.setFillColor(color.withMultipliedAlpha(0.45).cgColor)
            let track = CGRect(x: center - trackWidth / 2.0, y: 3.5, width: trackWidth, height: 17.0)
            context.addPath(UIBezierPath(roundedRect: track, cornerRadius: trackWidth / 2.0).cgPath)
            context.fillPath()

            context.setFillColor(color.cgColor)
            let cap = CGRect(x: center - capSize.width / 2.0, y: positions[index] - capSize.height / 2.0, width: capSize.width, height: capSize.height)
            context.addPath(UIBezierPath(roundedRect: cap, cornerRadius: capSize.height / 2.0).cgPath)
            context.fillPath()
        }
    })
}

func clearOpenEqualizer(parentController: ViewController?) {
    guard let playerController = parentController as? OverlayAudioPlayerControllerImpl,
          let navigationController = playerController.parentNavigationController else {
        return
    }

    let controller = clearEqualizerController(context: playerController.context)
    controller.navigationPresentation = .modal
    navigationController.pushViewController(controller)
}
