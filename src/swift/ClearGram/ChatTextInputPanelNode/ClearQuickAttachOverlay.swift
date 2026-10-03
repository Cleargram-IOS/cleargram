import Foundation
import UIKit
import AVFoundation
import CoreImage
import ComponentFlow
import Display

// Quick attach: hold the paperclip, the latest photos fan out of it, slide onto one and let go.
// Ported from the tg-attach prototype (github.com/mishanaer/tg-attach) with its animation kept
// as-is — the two-axis springs, the stagger, the defocus veil and the icon morph are the point of
// the feature. What changed: icon and tint come from the chat theme; the backdrop is the
// send-options menu's exactly (`ChatSendMessageContextScreen`) — a `BlurredBackgroundView` with
// the theme's context-menu dim colour over the blur, faded through alpha; and the paperclip button
// is the real one. The prototype drew a glass copy over it, but a fresh native glass view
// materialises over a few frames and loses its blur over an animating backdrop, so the backdrop
// gets a hole in the button's shape instead, the real glass shows through untouched, and only
// the icon is drawn here (the real icon hides for as long as the overlay is up).

// Two-axis trick: X and Y run on separate springs. A fast Y with overshoot plus a slower smooth X
// bends the straight line into an arc while both axes keep real spring physics, which a keyframed
// curve would throw away. Measured off the reference capture; cards are born at the icon centre.
enum ClearFanTuning {
    static let xStiffness: CGFloat = 320
    static let xDamping: CGFloat = 0.88
    static let yStiffness: CGFloat = 500
    static let yDamping: CGFloat = 0.60
    static let birthScale: CGFloat = 0.42
    static let staggerMs: CGFloat = 28
    static let birthYOffset: CGFloat = 0
    // Per-card Y damping reduction: the further right, the bouncier.
    static let yOvershootStep: CGFloat = 0.06
}

final class ClearQuickAttachOverlayView: UIView {
    struct Appearance {
        let attachIcon: UIImage?
        let iconTint: UIColor
        let dimColor: UIColor
    }

    private let dimView = BlurredBackgroundView(color: .clear, enableBlur: true)
    // Sits exactly over the real attach button, which shows through a hole in the backdrop; only
    // the icon morphs paperclip <-> × here.
    private let cancelButton = UIView()
    private let backdropHole = CAShapeLayer()
    private let attachIconView = UIImageView()
    private let cancelIcon = UIImageView()
    private let appearance: Appearance

    private var itemViews: [UIImageView] = []
    private var itemFrames: [CGRect] = []
    private var sourceRect: CGRect = .zero
    private var highlightedIndex: Int?
    private var cancelHighlighted = false
    private var hasCamera = false

    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

    private let itemSide: CGFloat = 68
    private let itemSpacing: CGFloat = 9
    private let stripBottomGap: CGFloat = 14
    private let hitSlop: CGFloat = 14

    init(frame: CGRect, appearance: Appearance) {
        self.appearance = appearance
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        self.dimView.frame = self.bounds
        self.dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.dimView.updateColor(color: appearance.dimColor, enableBlur: true, forceKeepBlur: true, transition: .immediate)
        self.dimView.update(size: self.bounds.size, transition: .immediate)
        self.backdropHole.fillRule = .evenOdd
        self.backdropHole.fillColor = UIColor.black.cgColor
        let maskView = UIView(frame: self.bounds)
        maskView.layer.addSublayer(self.backdropHole)
        self.dimView.mask = maskView
        self.dimView.alpha = 0.0
        self.addSubview(self.dimView)

        self.attachIconView.image = appearance.attachIcon
        self.attachIconView.tintColor = appearance.iconTint
        self.attachIconView.contentMode = .center
        self.cancelButton.addSubview(self.attachIconView)

        self.cancelIcon.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        self.cancelIcon.tintColor = appearance.iconTint
        self.cancelIcon.contentMode = .center
        self.cancelButton.addSubview(self.cancelIcon)
        self.addSubview(self.cancelButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var cameraIndex: Int? {
        return self.hasCamera ? 0 : nil
    }

    // MARK: - Presentation

    // `sourceRect` is the attach button's glass circle in this view's coordinates.
    func present(images: [UIImage], includeCamera: Bool, from sourceRect: CGRect) {
        self.sourceRect = sourceRect
        self.hasCamera = includeCamera
        self.impactHaptic.impactOccurred()
        self.selectionHaptic.prepare()

        // The real button is a 40pt circle, or a pill growing upward with the icon in its bottom
        // 40pt slot; the hole follows the shape, the icons the slot.
        self.cancelButton.frame = sourceRect
        let path = UIBezierPath(rect: self.bounds)
        path.append(UIBezierPath(roundedRect: sourceRect, cornerRadius: min(sourceRect.width, sourceRect.height) * 0.5))
        self.backdropHole.frame = self.bounds
        self.backdropHole.path = path.cgPath
        let iconSlot = CGRect(x: 0.0, y: sourceRect.height - sourceRect.width, width: sourceRect.width, height: sourceRect.width)
        self.attachIconView.frame = iconSlot
        self.cancelIcon.frame = iconSlot
        self.cancelButton.alpha = 1.0
        self.cancelButton.transform = .identity
        self.attachIconView.alpha = 1.0
        self.attachIconView.transform = .identity
        self.cancelIcon.alpha = 0.0
        self.cancelIcon.transform = CGAffineTransform(rotationAngle: -.pi / 2).scaledBy(x: 0.5, y: 0.5)

        var views: [UIImageView] = []
        if includeCamera {
            let cameraItem = ClearCameraStripItemView.shared
            cameraItem.removeFromSuperview()
            cameraItem.warmUp()
            views.append(cameraItem)
        }
        views.append(contentsOf: images.map { UIImageView(image: $0) })

        // The strip sits above the button, left-aligned to it.
        self.itemFrames = []
        let stripY = sourceRect.minY - self.stripBottomGap - self.itemSide
        var x = sourceRect.minX
        let maxX = self.bounds.width - 8 - self.itemSide
        for _ in 0 ..< views.count {
            self.itemFrames.append(CGRect(x: min(x, maxX), y: stripY, width: self.itemSide, height: self.itemSide))
            x += self.itemSide + self.itemSpacing
        }

        for view in views {
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.layer.cornerRadius = 14
            view.layer.cornerCurve = .continuous
            self.addSubview(view)
        }
        self.itemViews = views

        // Start state: every card spawns at the paperclip centre, rounded almost into a circle,
        // slightly blurred, leftmost on top.
        for (index, view) in self.itemViews.enumerated() {
            // The camera tile is reused between presentations and still carries the transform
            // baked in when the fan last folded. Assigning .frame under a scaled transform derives
            // bounds as frame / scale, which blows the tile up once the flight animates back to 1.
            view.layer.removeAllAnimations()
            view.transform = .identity
            view.frame = self.itemFrames[index]
            view.alpha = 0.0
            view.layer.cornerRadius = 34.0

            if !(view is ClearCameraStripItemView), let image = view.image, let blurred = Self.blurredImage(image, radius: 10) {
                let veil = UIImageView(image: blurred)
                veil.contentMode = .scaleAspectFill
                veil.clipsToBounds = true
                veil.frame = view.bounds
                veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                veil.tag = 777
                view.addSubview(veil)
            }
        }
        for view in self.itemViews.reversed() {
            self.bringSubviewToFront(view)
        }
        self.bringSubviewToFront(self.cancelButton)

        UIView.animate(withDuration: 0.12) {
            self.dimView.alpha = 1.0
        }
        // Explicit CA animations with an explicit fromValue: the × birth state is set in this same
        // runloop turn on a fresh layer, so a UIView animation would read the final value as its
        // "from" and pop the icon to full size in one frame.
        Self.morphIcon(self.attachIconView, fromScale: 1.0, toScale: 0.5, fromRotation: 0.0, toRotation: .pi / 2, fromAlpha: 1.0, toAlpha: 0.0)
        Self.morphIcon(self.cancelIcon, fromScale: 0.5, toScale: 1.0, fromRotation: -.pi / 2, toRotation: 0.0, fromAlpha: 0.0, toAlpha: 1.0)

        let source = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        for (index, view) in self.itemViews.enumerated() {
            let dest = view.center
            // Positive stagger: a wave left to right. Negative: rightmost launches first.
            let staggerStep = Double(ClearFanTuning.staggerMs) / 1000.0
            let order = staggerStep >= 0 ? Double(index) : Double(self.itemViews.count - 1 - index)
            let begin = CACurrentMediaTime() + order * abs(staggerStep)

            view.layer.add(Self.axisSpring("position.x", from: source.x, to: dest.x, stiffness: ClearFanTuning.xStiffness, dampingRatio: ClearFanTuning.xDamping, begin: begin), forKey: "flightX")
            let yDampingForCard = max(0.2, ClearFanTuning.yDamping - CGFloat(index) * ClearFanTuning.yOvershootStep)
            view.layer.add(Self.axisSpring("position.y", from: source.y + ClearFanTuning.birthYOffset, to: dest.y, stiffness: ClearFanTuning.yStiffness, dampingRatio: yDampingForCard, begin: begin), forKey: "flightY")
            view.layer.add(Self.axisSpring("transform.scale", from: ClearFanTuning.birthScale, to: 1.0, stiffness: ClearFanTuning.xStiffness, dampingRatio: ClearFanTuning.xDamping, begin: begin), forKey: "flightScale")

            let fadeDelay = max(0.0, begin - CACurrentMediaTime())
            UIView.animate(withDuration: 0.15, delay: fadeDelay, options: [.allowUserInteraction, .curveEaseOut]) {
                view.alpha = 1.0
            }

            // Circle -> square on the same spring as X, so the shape always matches the flight.
            let corner = Self.axisSpring("cornerRadius", from: 34.0, to: 14.0, stiffness: ClearFanTuning.xStiffness, dampingRatio: ClearFanTuning.xDamping, begin: begin)
            view.layer.add(corner, forKey: "cornerMorph")
            view.layer.cornerRadius = 14.0

            if let veil = view.viewWithTag(777) {
                let veilDuration = min(0.18, corner.settlingDuration * 0.4)
                UIView.animate(withDuration: veilDuration, delay: 0.0, options: [.allowUserInteraction, .curveEaseOut]) {
                    veil.alpha = 0.0
                } completion: { _ in
                    veil.removeFromSuperview()
                }
            }
        }
    }

    private static func axisSpring(_ keyPath: String, from: CGFloat, to: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat, begin: CFTimeInterval) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.fromValue = from
        spring.toValue = to
        spring.mass = 1.0
        spring.stiffness = stiffness
        spring.damping = dampingRatio * 2.0 * sqrt(stiffness)
        spring.duration = spring.settlingDuration
        spring.beginTime = begin
        spring.fillMode = .backwards
        return spring
    }

    // Pre-rendered gaussian blur for the birth defocus.
    private static func blurredImage(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        guard let rendered = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    // MARK: - Finger tracking

    func updateTracking(location: CGPoint) {
        let newIndex = self.itemIndex(at: location)
        let overCancel = newIndex == nil && self.isOverCancel(location)

        if newIndex != self.highlightedIndex {
            if newIndex != nil {
                self.selectionHaptic.selectionChanged()
            }
            self.highlightedIndex = newIndex
            for (index, view) in self.itemViews.enumerated() {
                let highlighted = index == newIndex
                UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
                    view.transform = highlighted ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity
                    view.layer.shadowOpacity = highlighted ? 0.25 : 0.0
                }
                if highlighted {
                    view.layer.shadowColor = UIColor.black.cgColor
                    view.layer.shadowRadius = 12
                    view.layer.shadowOffset = CGSize(width: 0, height: 6)
                    self.bringSubviewToFront(view)
                }
            }
        }

        if overCancel != self.cancelHighlighted {
            self.cancelHighlighted = overCancel
            if overCancel {
                self.selectionHaptic.selectionChanged()
            }
            UIView.animate(withDuration: 0.2, delay: 0.0, options: [.allowUserInteraction]) {
                self.cancelButton.transform = overCancel ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
            }
        }
    }

    // The index under the release point, or nil for cancel.
    func finishTracking(location: CGPoint) -> Int? {
        return self.itemIndex(at: location)
    }

    private func itemIndex(at location: CGPoint) -> Int? {
        for (index, frame) in self.itemFrames.enumerated() {
            if frame.insetBy(dx: -self.hitSlop, dy: -self.hitSlop * 2).contains(location) {
                return index
            }
        }
        return nil
    }

    private func isOverCancel(_ location: CGPoint) -> Bool {
        return self.sourceRect.insetBy(dx: -self.hitSlop, dy: -self.hitSlop).contains(location)
    }

    // MARK: - Icon morph

    // Current on-screen state of an icon: the presentation layer while the opening morph is still
    // running, the settled values otherwise. Lets a dismissal that interrupts the opening continue
    // from where the icon is.
    private static func iconState(_ view: UIView, scale: CGFloat, rotation: CGFloat, alpha: CGFloat) -> (scale: CGFloat, rotation: CGFloat, alpha: CGFloat) {
        guard let presentation = view.layer.presentation(), view.layer.animation(forKey: "morphScale") != nil else {
            return (scale, rotation, alpha)
        }
        let currentScale = (presentation.value(forKeyPath: "transform.scale.x") as? CGFloat) ?? scale
        let currentRotation = (presentation.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? rotation
        return (currentScale, currentRotation, CGFloat(presentation.opacity))
    }

    private static func morphIcon(_ view: UIView, fromScale: CGFloat, toScale: CGFloat, fromRotation: CGFloat, toRotation: CGFloat, fromAlpha: CGFloat, toAlpha: CGFloat) {
        let layer = view.layer
        let stiffness: CGFloat = 260
        let damping = 0.8 * 2.0 * sqrt(stiffness)

        func spring(_ keyPath: String, _ from: CGFloat, _ to: CGFloat) -> CASpringAnimation {
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.mass = 1.0
            animation.stiffness = stiffness
            animation.damping = damping
            animation.duration = animation.settlingDuration
            return animation
        }

        layer.add(spring("transform.scale", fromScale, toScale), forKey: "morphScale")
        layer.add(spring("transform.rotation.z", fromRotation, toRotation), forKey: "morphRotation")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromAlpha
        fade.toValue = toAlpha
        fade.duration = 0.25
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "morphFade")

        view.transform = CGAffineTransform(rotationAngle: toRotation).scaledBy(x: toScale, y: toScale)
        view.alpha = toAlpha
    }

    // MARK: - Dismissal

    // With `selectedIndex` and `targetRect`, the selected card flies into the composer slot while
    // the rest melt away; otherwise everything folds back into the button.
    func dismiss(selectedIndex: Int?, targetRect: CGRect?, completion: @escaping () -> Void) {
        // The flight springs may still be mid-air: bake each card's current presentation
        // position/scale into the model and drop the animations, so every dismissal path continues
        // from where the card is.
        for view in self.itemViews {
            if let presentation = view.layer.presentation() {
                let scale = (presentation.value(forKeyPath: "transform.scale.x") as? CGFloat) ?? 1.0
                view.layer.removeAnimation(forKey: "flightX")
                view.layer.removeAnimation(forKey: "flightY")
                view.layer.removeAnimation(forKey: "flightScale")
                view.layer.position = presentation.position
                view.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }

        UIView.animate(withDuration: 0.2, delay: 0.0) {
            self.dimView.alpha = 0.0
        }
        let cancelState = Self.iconState(self.cancelIcon, scale: 1.0, rotation: 0.0, alpha: 1.0)
        let attachState = Self.iconState(self.attachIconView, scale: 0.5, rotation: .pi / 2, alpha: 0.0)
        Self.morphIcon(self.cancelIcon, fromScale: cancelState.scale, toScale: 0.5, fromRotation: cancelState.rotation, toRotation: -.pi / 2, fromAlpha: cancelState.alpha, toAlpha: 0.0)
        Self.morphIcon(self.attachIconView, fromScale: attachState.scale, toScale: 1.0, fromRotation: attachState.rotation, toRotation: 0.0, fromAlpha: attachState.alpha, toAlpha: 1.0)
        UIView.animate(withDuration: 0.25, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4) {
            self.cancelButton.transform = .identity
        }

        for (index, view) in self.itemViews.enumerated() {
            if index == selectedIndex && targetRect != nil {
                continue
            }
            if selectedIndex == nil {
                // A true mirror of the opening: the same axis springs and stagger played
                // backwards — the card that launched last returns first.
                let target = CGPoint(x: self.sourceRect.midX, y: self.sourceRect.midY + ClearFanTuning.birthYOffset)
                let fromPos = view.layer.position
                let fromScale = view.transform.a
                let staggerStep = Double(ClearFanTuning.staggerMs) / 1000.0
                let reverseOrder = staggerStep >= 0 ? Double(self.itemViews.count - 1 - index) : Double(index)
                let begin = CACurrentMediaTime() + reverseOrder * abs(staggerStep)

                // To retrace the same arc the axes swap speeds: outbound the fast axis is Y (steep
                // take-off), so on the way back it is X (slide along the row, then drop into the
                // paperclip).
                let yDampingForCard = max(0.2, ClearFanTuning.yDamping - CGFloat(index) * ClearFanTuning.yOvershootStep)
                view.layer.position = target
                view.transform = CGAffineTransform(scaleX: ClearFanTuning.birthScale, y: ClearFanTuning.birthScale)
                view.layer.add(Self.axisSpring("position.x", from: fromPos.x, to: target.x, stiffness: ClearFanTuning.yStiffness, dampingRatio: yDampingForCard, begin: begin), forKey: "foldX")
                view.layer.add(Self.axisSpring("position.y", from: fromPos.y, to: target.y, stiffness: ClearFanTuning.xStiffness, dampingRatio: ClearFanTuning.xDamping, begin: begin), forKey: "foldY")
                view.layer.add(Self.axisSpring("transform.scale", from: fromScale, to: ClearFanTuning.birthScale, stiffness: ClearFanTuning.xStiffness, dampingRatio: ClearFanTuning.xDamping, begin: begin), forKey: "foldScale")
                view.layer.add(Self.axisSpring("cornerRadius", from: view.layer.cornerRadius, to: 34.0, stiffness: ClearFanTuning.xStiffness, dampingRatio: ClearFanTuning.xDamping, begin: begin), forKey: "cornerFold")
                view.layer.cornerRadius = 34.0

                let fadeDelay = max(0.0, begin - CACurrentMediaTime())
                UIView.animate(withDuration: 0.10, delay: fadeDelay, options: [.curveEaseOut]) {
                    view.alpha = 0.0
                }
                // Defocus-out: the blurred copy ramps in over the same 100ms — the mirror of the spawn.
                if !(view is ClearCameraStripItemView), let image = view.image, let blurred = Self.blurredImage(image, radius: 10) {
                    let veil = UIImageView(image: blurred)
                    veil.contentMode = .scaleAspectFill
                    veil.clipsToBounds = true
                    veil.frame = view.bounds
                    veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    veil.alpha = 0.0
                    view.addSubview(veil)
                    UIView.animate(withDuration: 0.10, delay: fadeDelay, options: [.curveEaseOut]) {
                        veil.alpha = 1.0
                    }
                }
            } else {
                UIView.animate(withDuration: 0.10, delay: 0.0, options: [.curveEaseOut]) {
                    view.alpha = 0.0
                    view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                }
            }
        }

        if let selectedIndex, let targetRect, selectedIndex < self.itemViews.count {
            let selected = self.itemViews[selectedIndex]
            self.bringSubviewToFront(selected)

            // The × badge fades in on the flying thumbnail so it arrives together with the image.
            let side = ClearAttachmentBadge.side
            let badge = UIView()
            badge.backgroundColor = ClearAttachmentBadge.circleColor
            badge.layer.cornerRadius = ClearAttachmentBadge.cornerRadius
            let badgeIcon = ClearAttachmentBadge.makeIcon()
            badgeIcon.frame = CGRect(x: 0, y: 0, width: side, height: side)
            badge.addSubview(badgeIcon)
            badge.frame = CGRect(x: selected.bounds.width - side - ClearAttachmentBadge.inset, y: ClearAttachmentBadge.inset, width: side, height: side)
            badge.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            badge.alpha = 0.0
            selected.addSubview(badge)
            UIView.animate(withDuration: 0.32) {
                badge.alpha = 1.0
            }

            let cornerAnimation = CABasicAnimation(keyPath: "cornerRadius")
            cornerAnimation.fromValue = selected.layer.cornerRadius
            cornerAnimation.toValue = ClearAttachmentBadge.thumbnailCornerRadius
            cornerAnimation.duration = 0.25
            selected.layer.add(cornerAnimation, forKey: "cornerRadius")
            selected.layer.cornerRadius = ClearAttachmentBadge.thumbnailCornerRadius

            UIView.animate(withDuration: 0.32, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4, options: []) {
                selected.transform = .identity
                selected.frame = targetRect
                selected.layer.shadowOpacity = 0.0
            } completion: { _ in
                ClearCameraStripItemView.shared.scheduleCooldown()
                self.removeFromSuperview()
                completion()
            }
        } else {
            // Cards are fully faded by ~0.45s; no need to hold the overlay longer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                ClearCameraStripItemView.shared.scheduleCooldown()
                self.removeFromSuperview()
                completion()
            }
        }
    }
}

// The × badge on an attachment thumbnail. The overlay draws one on the flying card and the
// composer draws the real one on the landed thumbnail; the two swap at the end of the flight, so
// both come from here — a UIButton renders the same symbol at its own point size and the swap
// shows up as the badge jumping a size in one frame.
enum ClearAttachmentBadge {
    static let side: CGFloat = 22
    static let cornerRadius: CGFloat = 11
    static let inset: CGFloat = 4
    static let circleColor = UIColor(white: 0.0, alpha: 0.4)
    static let thumbnailCornerRadius: CGFloat = 10

    static func makeIcon() -> UIImageView {
        let icon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        return icon
    }
}

// Live camera tile: a real viewfinder where a camera exists and access was already granted, a dark
// placeholder with the camera icon otherwise. Never prompts for access itself — the stock camera
// the tile opens does that.
final class ClearCameraStripItemView: UIImageView {
    // One instance for the whole app: the capture session survives between presentations, so a
    // warmed-up viewfinder is still live next time.
    static let shared = ClearCameraStripItemView()

    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let iconView = UIImageView()
    private var cooldownTimer: Timer?

    // Start the camera ahead of the card — called on the paperclip's touch-down, a press duration
    // before the fan opens.
    func warmUp() {
        self.cooldownTimer?.invalidate()
        self.cooldownTimer = nil
        self.setupSessionIfAllowed()
        guard let session = self.session, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    // Stop it a few seconds after the overlay is gone, so the camera and its privacy indicator do
    // not stay on for a fan nobody opened again.
    func scheduleCooldown() {
        self.cooldownTimer?.invalidate()
        self.cooldownTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let session = self?.session, session.isRunning else { return }
            DispatchQueue.global(qos: .utility).async {
                session.stopRunning()
            }
        }
    }

    private init() {
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false
        self.backgroundColor = UIColor(white: 0.10, alpha: 1.0)

        self.iconView.image = UIImage(systemName: "camera.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        self.iconView.tintColor = .white
        self.iconView.contentMode = .center
        self.addSubview(self.iconView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupSessionIfAllowed() {
        guard self.session == nil, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.insertSublayer(layer, at: 0)
        self.session = session
        self.previewLayer = layer
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.iconView.frame = self.bounds
        self.previewLayer?.frame = self.bounds
        self.iconView.isHidden = self.previewLayer != nil
    }
}
