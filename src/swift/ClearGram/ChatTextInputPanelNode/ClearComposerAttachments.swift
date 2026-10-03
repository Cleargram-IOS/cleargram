import Foundation
import UIKit
import Photos
import SwiftSignalKit
import Display
import LegacyComponents
import TelegramPresentationData
import GlassBackgroundComponent
import TelegramUIPreferences

// Attachments in the input field: picked media waits as thumbnails inside the glass field and goes
// out with the text as its caption.
//
// The state is the same pair of contexts the stock media picker runs on — a selection context for
// what is attached and an editing context for what was done to it. That is what lets the
// full-screen editor, the picker and the send path all be stock: they already speak this pair.
// It lives on the panel, i.e. per open chat, in memory only — drafts sync through the server and
// cannot carry local media.
public final class ClearComposerAttachments {
    public static let selectionLimit: Int32 = 10

    public let selectionContext: TGMediaSelectionContext
    public private(set) var editingContext: TGMediaEditingContext
    var onUpdate: (() -> Void)?
    private var selectionDisposable: SDisposable?

    init() {
        self.selectionContext = TGMediaSelectionContext(groupingAllowed: true, selectionLimit: ClearComposerAttachments.selectionLimit)!
        // Several photos go out as one album, as from the picker.
        self.selectionContext.grouping = true
        self.editingContext = TGMediaEditingContext()
        // The stock gallery can deselect an item through its own check mark, so the strip follows
        // the context rather than our own add/remove calls.
        self.selectionDisposable = self.selectionContext.selectionChangedSignal().start(next: { [weak self] _ in
            Queue.mainQueue().async {
                self?.onUpdate?()
            }
        }, error: nil, completed: nil)
    }

    deinit {
        self.selectionDisposable?.dispose()
    }

    public var items: [TGMediaSelectableItem & TGMediaEditableItem] {
        return (self.selectionContext.selectedItems() ?? []).compactMap { $0 as? TGMediaSelectableItem & TGMediaEditableItem }
    }

    public var isEmpty: Bool {
        return self.selectionContext.count() == 0
    }

    @discardableResult
    func add(_ item: TGMediaSelectableItem) -> Bool {
        self.dropPickerGate()
        return self.selectionContext.setItem(item, selected: true)
    }

    func remove(_ item: TGMediaSelectableItem) {
        self.dropPickerGate()
        self.selectionContext.setItem(item, selected: false)
    }

    // The stock picker, running on this context, installs `attemptSelectingItem` — and TGMediaSelectionContext
    // asks it on deselection too, not only on selection. It holds the picker weakly and answers
    // false once the picker is gone, which froze the context: nothing could be removed, and a sent
    // video stayed in the field. Every change made from here happens with no picker open, and the
    // next picker installs its own gate again.
    private func dropPickerGate() {
        self.selectionContext.attemptSelectingItem = nil
    }

    // After a send: drop the items and start a fresh editing context, so crops and captions of the
    // sent media do not leak into the next attachment of the same asset.
    public func clear() {
        self.dropPickerGate()
        self.selectionContext.clear()
        self.editingContext = TGMediaEditingContext()
        self.onUpdate?()
    }
}

// Both TGMediaSelectableItem and TGMediaEditableItem declare `uniqueIdentifier`, which makes the
// member ambiguous on their composition; go through one of them.
func clearItemId(_ item: TGMediaEditableItem) -> String {
    return item.uniqueIdentifier ?? ""
}

// The thumbnail row at the top of the input field.
final class ClearComposerAttachmentStripView: UIView {
    static let chipSide: CGFloat = 64
    static let inset: CGFloat = 8
    static let spacing: CGFloat = 8
    static let height: CGFloat = inset + chipSide

    private final class ChipView: UIView {
        let imageView = UIImageView()
        let removeButton = UIButton(type: .custom)
        var thumbnailDisposable: Disposable?

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.imageView.contentMode = .scaleAspectFill
            self.imageView.clipsToBounds = true
            self.imageView.layer.cornerRadius = ClearAttachmentBadge.thumbnailCornerRadius
            self.imageView.layer.cornerCurve = .continuous
            self.imageView.backgroundColor = UIColor(white: 0.5, alpha: 0.2)
            self.addSubview(self.imageView)

            self.removeButton.backgroundColor = ClearAttachmentBadge.circleColor
            self.removeButton.layer.cornerRadius = ClearAttachmentBadge.cornerRadius
            let icon = ClearAttachmentBadge.makeIcon()
            icon.frame = CGRect(x: 0, y: 0, width: ClearAttachmentBadge.side, height: ClearAttachmentBadge.side)
            self.removeButton.addSubview(icon)
            self.addSubview(self.removeButton)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        deinit {
            self.thumbnailDisposable?.dispose()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            self.imageView.frame = self.bounds
            let side = ClearAttachmentBadge.side
            self.removeButton.frame = CGRect(x: self.bounds.width - side - ClearAttachmentBadge.inset, y: ClearAttachmentBadge.inset, width: side, height: side)
        }

        // The badge is small; the finger gets a bit more.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            return self.bounds.insetBy(dx: -4.0, dy: -4.0).contains(point)
        }
    }

    private let scrollView = UIScrollView()
    private var chips: [String: ChipView] = [:]
    private var order: [String] = []
    private var itemsById: [String: TGMediaSelectableItem & TGMediaEditableItem] = [:]
    // A chip whose image is still in the air on the quick-attach card; revealed when it lands.
    private var pendingRevealId: String?
    private(set) var hiddenId: String?

    var onTap: ((TGMediaSelectableItem & TGMediaEditableItem, UIView) -> Void)?
    var onRemove: ((TGMediaSelectableItem & TGMediaEditableItem) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.scrollView.clipsToBounds = false
        self.addSubview(self.scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func markPendingReveal(_ id: String) {
        self.pendingRevealId = id
        self.chips[id]?.alpha = 0.0
    }

    func reveal(_ id: String) {
        if self.pendingRevealId == id {
            self.pendingRevealId = nil
        }
        // The badge already arrived on the flying card — show the real one at once, no pop.
        if id != self.hiddenId {
            self.chips[id]?.alpha = 1.0
        }
    }

    // Hidden while the full-screen editor shows the same item, so the transition reads as the
    // thumbnail itself expanding.
    func setHidden(id: String?) {
        let previous = self.hiddenId
        self.hiddenId = id
        if let previous, previous != self.pendingRevealId {
            self.chips[previous]?.alpha = 1.0
        }
        if let id {
            self.chips[id]?.alpha = 0.0
        }
    }

    func imageView(for id: String) -> UIView? {
        return self.chips[id]?.imageView
    }

    func chipFrame(for id: String, in view: UIView) -> CGRect? {
        guard let chip = self.chips[id] else { return nil }
        return chip.convert(chip.bounds, to: view)
    }

    func update(items: [TGMediaSelectableItem & TGMediaEditableItem], editingContext: TGMediaEditingContext, size: CGSize, transition: ContainedViewLayoutTransition) {
        let ids = items.map { clearItemId($0) }
        var itemsById: [String: TGMediaSelectableItem & TGMediaEditableItem] = [:]
        for (id, item) in zip(ids, items) {
            itemsById[id] = item
        }
        self.itemsById = itemsById

        for (id, chip) in self.chips where itemsById[id] == nil {
            self.chips[id] = nil
            // Removal blinks out fast (~70ms); the field then springs back down around it.
            UIView.animate(withDuration: 0.07, delay: 0.0, options: [.curveLinear]) {
                chip.alpha = 0.0
            } completion: { _ in
                chip.removeFromSuperview()
            }
        }

        transition.updateFrame(view: self.scrollView, frame: CGRect(origin: CGPoint(), size: size))

        let side = ClearComposerAttachmentStripView.chipSide
        let inset = ClearComposerAttachmentStripView.inset
        var x = inset
        for id in ids {
            guard let item = itemsById[id] else { continue }
            let frame = CGRect(x: x, y: inset, width: side, height: side)
            x += side + ClearComposerAttachmentStripView.spacing
            if let chip = self.chips[id] {
                transition.updateFrame(view: chip, frame: frame)
            } else {
                let chip = ChipView(frame: frame)
                chip.alpha = (id == self.pendingRevealId || id == self.hiddenId) ? 0.0 : 1.0
                chip.removeButton.addTarget(self, action: #selector(self.removePressed(_:)), for: .touchUpInside)
                chip.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.chipTapped(_:))))
                self.chips[id] = chip
                self.scrollView.addSubview(chip)
                chip.thumbnailDisposable = (Self.thumbnail(for: item, editingContext: editingContext, side: side)
                |> deliverOnMainQueue).start(next: { [weak chip] image in
                    if let image {
                        chip?.imageView.image = image
                    }
                })
            }
        }
        self.order = ids
        self.scrollView.contentSize = CGSize(width: x - ClearComposerAttachmentStripView.spacing + inset, height: size.height)
        if let pendingRevealId = self.pendingRevealId, let chip = self.chips[pendingRevealId] {
            self.scrollView.scrollRectToVisible(chip.frame.insetBy(dx: -inset, dy: 0.0), animated: false)
        }
    }

    // The edited thumbnail if the editor has produced one, the asset's own image otherwise — the
    // same fallback the picker's selected-items list uses.
    static func thumbnail(for item: TGMediaSelectableItem & TGMediaEditableItem, editingContext: TGMediaEditingContext, side: CGFloat) -> Signal<UIImage?, NoError> {
        let identifier = clearItemId(item)
        let edited = Signal<UIImage?, NoError> { subscriber in
            guard let signal = editingContext.thumbnailImageSignal(forIdentifier: identifier) else {
                subscriber.putNext(nil)
                return EmptyDisposable
            }
            let disposable = signal.start(next: { next in
                subscriber.putNext(next as? UIImage)
            }, error: { _ in
            }, completed: nil)
            return ActionDisposable {
                disposable?.dispose()
            }
        }

        let original: Signal<UIImage?, NoError>
        if let asset = item as? TGMediaAsset, let backingAsset = asset.backingAsset {
            let scale = min(2.0, UIScreen.main.scale)
            let targetSize = CGSize(width: side * scale * 2.0, height: side * scale * 2.0)
            original = Signal { subscriber in
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                let requestId = PHImageManager.default().requestImage(for: backingAsset, targetSize: targetSize, contentMode: .aspectFill, options: options, resultHandler: { image, _ in
                    subscriber.putNext(image)
                })
                return ActionDisposable {
                    PHImageManager.default().cancelImageRequest(requestId)
                }
            }
        } else {
            original = Signal { subscriber in
                let disposable = item.screenImageSignal?(0.0)?.start(next: { next in
                    subscriber.putNext(next as? UIImage)
                }, error: { _ in
                }, completed: nil)
                return ActionDisposable {
                    disposable?.dispose()
                }
            }
        }

        return combineLatest(edited, original)
        |> map { edited, original -> UIImage? in
            return edited ?? original
        }
    }

    @objc private func removePressed(_ sender: UIButton) {
        guard let chip = sender.superview as? ChipView, let id = self.chips.first(where: { $0.value === chip })?.key, let item = self.itemsById[id] else { return }
        self.onRemove?(item)
    }

    @objc private func chipTapped(_ gesture: UITapGestureRecognizer) {
        guard let chip = gesture.view as? ChipView, let id = self.chips.first(where: { $0.value === chip })?.key, let item = self.itemsById[id] else { return }
        self.onTap?(item, chip.imageView)
    }
}

// Everything the input panel needs from this feature, behind one object it owns. The stock panel
// only holds it, installs it, asks it for the strip's height during layout and whether there is
// something to send; the rest stays here.
public final class ClearComposerPanel: NSObject, UIGestureRecognizerDelegate {
    public let attachments = ClearComposerAttachments()
    private let stripView = ClearComposerAttachmentStripView()

    private weak var panel: ChatTextInputPanelNode?
    private var theme: PresentationTheme?
    private var overlay: ClearQuickAttachOverlayView?
    private var recentPhotos: [(asset: PHAsset, image: UIImage)] = []
    private let imageManager = PHCachingImageManager()

    // Set by the chat controller: open the stock full-screen editor on an attached item, open the
    // stock camera.
    public var openItem: ((TGMediaSelectableItem & TGMediaEditableItem, UIView) -> Void)?
    public var openCamera: (() -> Void)?

    // Default-off: with the toggle off the panel never shows the strip and never reports items, so
    // send and layout run exactly as stock.
    public var hasItems: Bool {
        return ClearConfig.composerAttachments && !self.attachments.isEmpty
    }

    // How much the strip adds to the panel's height; 0 when nothing is attached. The chat keeps
    // its bottom edge dimming at the stock height by taking this back off.
    public var stripHeight: CGFloat {
        return self.hasItems ? ClearComposerAttachmentStripView.height : 0.0
    }

    public override init() {
        super.init()
        self.stripView.alpha = 0.0
        // `requestLayout` would only re-lay the panel inside its current frame; a change in height
        // has to go through `updateHeight`, which is what makes the chat resize the panel.
        self.attachments.onUpdate = { [weak self] in
            self?.panel?.updateHeight(true)
        }
        self.stripView.onRemove = { [weak self] item in
            self?.attachments.remove(item)
        }
        self.stripView.onTap = { [weak self] item, view in
            self?.openItem?(item, view)
        }
    }

    public func install(panel: ChatTextInputPanelNode) {
        self.panel = panel
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.15
        longPress.delegate = self
        panel.attachmentButton.addGestureRecognizer(longPress)
        panel.attachmentButton.addTarget(self, action: #selector(self.attachmentTouchDown), for: .touchDown)
    }

    // MARK: - Editor transition

    public func transitionView(for identifier: String) -> UIView? {
        return self.stripView.imageView(for: identifier)
    }

    public func setHiddenItem(id: String?) {
        self.stripView.setHidden(id: id)
    }

    // MARK: - Layout

    // Lays the strip out at `y` inside the field and returns the height it takes; 0 when there is
    // nothing attached, which leaves the field exactly as stock.
    public func layoutStrip(container: UIView, y: CGFloat, width: CGFloat, theme: PresentationTheme, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.theme = theme
        if self.stripView.superview !== container {
            container.addSubview(self.stripView)
        }
        let height = ClearComposerAttachmentStripView.height
        let frame = CGRect(x: 0.0, y: y, width: width, height: height)
        guard self.hasItems else {
            if self.stripView.alpha != 0.0 {
                transition.updateAlpha(layer: self.stripView.layer, alpha: 0.0)
                self.stripView.update(items: [], editingContext: self.attachments.editingContext, size: frame.size, transition: transition)
            }
            return 0.0
        }
        if self.stripView.alpha == 0.0 {
            self.stripView.frame = frame
        }
        transition.updateFrame(view: self.stripView, frame: frame)
        self.stripView.alpha = 1.0
        self.stripView.update(items: self.attachments.items, editingContext: self.attachments.editingContext, size: frame.size, transition: transition)
        return height
    }

    // MARK: - Quick attach

    private var photoAccess: Bool {
        if #available(iOS 14.0, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            return status == .authorized || status == .limited
        } else {
            return PHPhotoLibrary.authorizationStatus() == .authorized
        }
    }

    // Only on the plain attach button: while a voice draft is shown the same button deletes it.
    // Without photo access the press stays a tap, and the stock menu asks for access as it does.
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard ClearConfig.composerAttachments, self.photoAccess, self.overlay == nil, let panel = self.panel, panel.view.window != nil else {
            return false
        }
        return panel.clearAttachButtonIsPlain
    }

    @objc private func attachmentTouchDown() {
        guard ClearConfig.composerAttachments, self.panel?.clearAttachButtonIsPlain == true else { return }
        if self.photoAccess {
            self.prefetchRecentPhotos()
        }
        if ClearConfig.quickAttachCamera {
            ClearCameraStripItemView.shared.warmUp()
        }
    }

    private var photoCount: Int {
        return ClearConfig.quickAttachCamera ? 3 : 4
    }

    private func prefetchRecentPhotos() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = self.photoCount
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        guard fetchResult.count > 0 else {
            self.recentPhotos = []
            return
        }
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 68.0 * scale * 2.0, height: 68.0 * scale * 2.0)
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = true

        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        var results: [String: UIImage] = [:]
        let group = DispatchGroup()
        for asset in assets {
            group.enter()
            self.imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { image, _ in
                if let image {
                    results[asset.localIdentifier] = image
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let ordered = assets.compactMap { asset -> (asset: PHAsset, image: UIImage)? in
                guard let image = results[asset.localIdentifier] else { return nil }
                return (asset, image)
            }
            self?.recentPhotos = ordered
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let window = self.panel?.view.window else { return }
        switch gesture.state {
        case .began:
            self.presentQuickAttach(in: window)
        case .changed:
            self.overlay?.updateTracking(location: gesture.location(in: window))
        case .ended:
            self.finishQuickAttach(location: gesture.location(in: window))
        case .cancelled, .failed:
            self.cancelQuickAttach()
        default:
            break
        }
    }

    private func presentQuickAttach(in window: UIWindow) {
        guard self.overlay == nil, let panel = self.panel, let theme = self.theme else { return }
        let includeCamera = ClearConfig.quickAttachCamera
        let photos = Array(self.recentPhotos.prefix(self.photoCount))
        guard includeCamera || !photos.isEmpty else { return }

        let appearance = ClearQuickAttachOverlayView.Appearance(
            attachIcon: PresentationResourcesChat.chatInputPanelAttachmentButtonImage(theme),
            iconTint: theme.chat.inputPanel.panelControlColor,
            dimColor: theme.contextMenu.dimColor
        )
        let overlay = ClearQuickAttachOverlayView(frame: window.bounds, appearance: appearance)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        self.overlay = overlay
        self.overlayPhotos = photos

        // The real glass stays untouched and shows through the overlay's backdrop; only its icon
        // hides, since the overlay morphs its own copy in the same spot. Never the glass itself:
        // taking native glass through alpha 0 cost it its rim, and a glass copy on top stacked
        // two translucent circles and materialised without blur.
        let background = panel.attachmentButtonBackground
        let sourceRect = background.convert(background.bounds, to: window)
        panel.clearAttachmentButtonIcon.isHidden = true
        overlay.present(images: photos.map(\.image), includeCamera: includeCamera, from: sourceRect)
    }

    private var overlayPhotos: [(asset: PHAsset, image: UIImage)] = []

    private func finishQuickAttach(location: CGPoint) {
        guard let overlay = self.overlay, let window = overlay.window else { return }
        guard let selectedIndex = overlay.finishTracking(location: location) else {
            self.cancelQuickAttach()
            return
        }
        if selectedIndex == overlay.cameraIndex {
            self.cancelQuickAttach()
            self.openCamera?()
            return
        }
        let photoIndex = selectedIndex - (overlay.cameraIndex == nil ? 0 : 1)
        guard photoIndex >= 0, photoIndex < self.overlayPhotos.count, let item = TGMediaAsset(phAsset: self.overlayPhotos[photoIndex].asset), let id = item.uniqueIdentifier else {
            self.cancelQuickAttach()
            return
        }

        let stripWasVisible = self.hasItems
        let alreadyAttached = self.attachments.selectionContext.isItemSelected(item)
        guard alreadyAttached || self.attachments.add(item) else {
            self.cancelQuickAttach()
            return
        }

        // Lay the field out in its final state first, so the card has a slot to land in. The
        // spring matches the card's flight (0.32s, damping 0.82). The chat resizes the panel a
        // runloop later (via `updateHeight`); the panel is pinned to the bottom, so when the strip
        // first appears the whole panel — the slot with it — ends up one strip-height higher.
        self.stripView.markPendingReveal(id)
        self.panel?.requestLayout(transition: .animated(duration: 0.32, curve: .spring))
        var targetRect = self.stripView.chipFrame(for: id, in: window)
        if !stripWasVisible {
            targetRect = targetRect?.offsetBy(dx: 0.0, dy: -ClearComposerAttachmentStripView.height)
        }

        overlay.dismiss(selectedIndex: selectedIndex, targetRect: targetRect) { [weak self] in
            guard let self else { return }
            self.stripView.reveal(id)
            self.overlayDidDisappear()
        }
    }

    private func cancelQuickAttach() {
        guard let overlay = self.overlay else { return }
        overlay.dismiss(selectedIndex: nil, targetRect: nil) { [weak self] in
            self?.overlayDidDisappear()
        }
    }

    private func overlayDidDisappear() {
        self.overlay = nil
        self.overlayPhotos = []
        self.panel?.clearAttachmentButtonIcon.isHidden = false
    }
}
