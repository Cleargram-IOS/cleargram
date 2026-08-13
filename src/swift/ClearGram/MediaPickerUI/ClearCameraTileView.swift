import Foundation
import UIKit
import Display
import TelegramPresentationData

// Stand-in for the stock camera tile in the attachment media picker.
//
// Stock draws a live `TGAttachmentCameraView` two grid cells tall and keeps an AVCaptureSession
// running for as long as the picker is open (battery, plus the system camera-in-use indicator).
// With `ClearConfig.compactGalleryCamera` the tile shrinks to a single square cell and this view is
// used instead: a placeholder-coloured square with a static camera glyph and no AVFoundation
// involvement at all.
//
// Tapping opens the camera through `openCamera?(nil)` — the same path the "Open Camera" button on
// the no-access placeholder uses. `nil` is an explicitly supported argument; every preview-
// transition use of the camera view is already `if let`-guarded. The only thing lost versus stock
// is the preview→fullscreen zoom animation, which is meaningless without a preview.
final class ClearCameraTileView: UIView {
    private let iconView = UIImageView()
    private let pressed: () -> Void
    private var iconColor: UIColor = .white
    private var iconPointSize: CGFloat = 0.0

    init(theme: PresentationTheme, pressed: @escaping () -> Void) {
        self.pressed = pressed

        super.init(frame: CGRect())

        self.clipsToBounds = true
        self.iconView.isUserInteractionEnabled = false
        self.iconView.contentMode = .scaleAspectFit
        self.addSubview(self.iconView)

        self.updateTheme(theme)

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.handleTap)))
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func updateTheme(_ theme: PresentationTheme) {
        // The same grey the grid's own photo placeholders use.
        self.backgroundColor = theme.list.mediaPlaceholderColor
        self.iconColor = theme.list.itemAccentColor
        // Invalidate the cached glyph: the point size hasn't changed, but the colour has.
        self.iconPointSize = 0.0
        self.setNeedsLayout()
    }

    @objc private func handleTap() {
        self.pressed()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // The glyph is rebuilt at the point size the cell actually needs. The bundle asset is a PDF
        // that the asset catalog rasterises at its natural size, so scaling it up to fill the tile
        // came out blurry; an SF Symbol stays vector at any size.
        let pointSize = floor(min(self.bounds.width, self.bounds.height) * 0.34)
        if pointSize > 0.0, pointSize != self.iconPointSize || self.iconView.image == nil {
            self.iconPointSize = pointSize
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            self.iconView.image = UIImage(systemName: "camera.fill", withConfiguration: configuration)?
                .withTintColor(self.iconColor, renderingMode: .alwaysOriginal)
        }

        guard let image = self.iconView.image, image.size.width > 0.0 else {
            return
        }
        self.iconView.frame = CGRect(
            origin: CGPoint(
                x: floorToScreenPixels((self.bounds.width - image.size.width) / 2.0),
                y: floorToScreenPixels((self.bounds.height - image.size.height) / 2.0)
            ),
            size: image.size
        )
    }
}
