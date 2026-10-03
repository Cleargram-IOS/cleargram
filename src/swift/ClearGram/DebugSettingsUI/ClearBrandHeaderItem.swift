import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import ItemListUI
import TelegramPresentationData

// The top of Cleargram Settings: the app logo, the name, and which build this is — the upstream
// release with this build's number, then the two commits it was assembled from. Sits on the list
// background, not on a card. Long-press copies the build lines, as the footer that used to carry
// them did.
//
// The logo is drawn rather than loaded: the only raster copies in the bundle are the 60pt
// alternate-icon PNGs (180px at @3x), which go soft at this size. It is the same vector the app
// icon is built from (`Telegram.icon`: `Placeholder.svg` on the `system-dark` fill) — a white arc
// of radius 300 and stroke 96 on a 1024 canvas, opening to the right between -50° and +50°.
final class ClearBrandHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let caption: String
    let sectionId: ItemListSectionId
    let copy: () -> Void

    init(theme: PresentationTheme, title: String, caption: String, sectionId: ItemListSectionId, copy: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.caption = caption
        self.sectionId = sectionId
        self.copy = copy
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ClearBrandHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ClearBrandHeaderItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params)
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

private final class ClearBrandHeaderItemNode: ListViewItemNode {
    private static let logoSide: CGFloat = 100.0
    private static let topInset: CGFloat = 8.0
    private static let titleSpacing: CGFloat = 14.0
    private static let captionSpacing: CGFloat = 6.0
    private static let bottomInset: CGFloat = 12.0
    private static let sideInset: CGFloat = 24.0

    private let logoNode: ASImageNode
    private let titleNode: TextNode
    private let captionNode: TextNode
    private var item: ClearBrandHeaderItem?

    init() {
        self.logoNode = ASImageNode()
        self.logoNode.displaysAsynchronously = false
        self.logoNode.image = ClearBrandHeaderItemNode.logoImage(side: ClearBrandHeaderItemNode.logoSide)
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.captionNode = TextNode()
        self.captionNode.isUserInteractionEnabled = false

        super.init(layerBacked: false)

        self.addSubnode(self.logoNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.captionNode)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.longPressed(_:))))
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            self.item?.copy()
        }
    }

    func asyncLayout() -> (_ item: ClearBrandHeaderItem, _ params: ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeCaptionLayout = TextNode.asyncLayout(self.captionNode)

        return { item, params in
            let available = max(1.0, params.width - params.leftInset - params.rightInset - ClearBrandHeaderItemNode.sideInset * 2.0)
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: item.title, font: Font.bold(28.0), textColor: item.theme.list.itemPrimaryTextColor),
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: available, height: .greatestFiniteMagnitude),
                alignment: .center
            ))
            let (captionLayout, captionApply) = makeCaptionLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: item.caption, font: Font.regular(13.0), textColor: item.theme.list.freeTextColor),
                maximumNumberOfLines: 0,
                truncationType: .end,
                constrainedSize: CGSize(width: available, height: .greatestFiniteMagnitude),
                alignment: .center,
                lineSpacing: 0.15
            ))

            let height = ClearBrandHeaderItemNode.topInset
                + ClearBrandHeaderItemNode.logoSide
                + ClearBrandHeaderItemNode.titleSpacing
                + titleLayout.size.height
                + ClearBrandHeaderItemNode.captionSpacing
                + captionLayout.size.height
                + ClearBrandHeaderItemNode.bottomInset
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: UIEdgeInsets())

            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                let _ = titleApply()
                let _ = captionApply()

                let logoSide = ClearBrandHeaderItemNode.logoSide
                var y = ClearBrandHeaderItemNode.topInset
                self.logoNode.frame = CGRect(x: floor((params.width - logoSide) / 2.0), y: y, width: logoSide, height: logoSide)
                y += logoSide + ClearBrandHeaderItemNode.titleSpacing
                self.titleNode.frame = CGRect(origin: CGPoint(x: floor((params.width - titleLayout.size.width) / 2.0), y: y), size: titleLayout.size)
                y += titleLayout.size.height + ClearBrandHeaderItemNode.captionSpacing
                self.captionNode.frame = CGRect(origin: CGPoint(x: floor((params.width - captionLayout.size.width) / 2.0), y: y), size: captionLayout.size)
            })
        }
    }

    static func logoImage(side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cg = context.cgContext
            let bounds = CGRect(x: 0.0, y: 0.0, width: side, height: side)
            // iOS app icon squircle: continuous corners at ~22.4% of the side.
            let shape = UIBezierPath(roundedRect: bounds, cornerRadius: side * 0.2237)
            shape.addClip()

            // `system-dark` fill: a near-black vertical gradient.
            let colors = [UIColor(rgb: 0x3a3a3c).cgColor, UIColor(rgb: 0x111113).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: side * 0.5, y: 0.0), end: CGPoint(x: side * 0.5, y: side), options: [])
            }

            let scale = side / 1024.0
            let arc = UIBezierPath(
                arcCenter: CGPoint(x: 512.0 * scale, y: 512.0 * scale),
                radius: 300.0 * scale,
                startAngle: -50.0 * .pi / 180.0,
                endAngle: 50.0 * .pi / 180.0,
                clockwise: false
            )
            arc.lineWidth = 96.0 * scale
            arc.lineCapStyle = .round
            cg.setShadow(offset: CGSize(width: 0.0, height: side * 0.01), blur: side * 0.04, color: UIColor(white: 0.0, alpha: 0.5).cgColor)
            UIColor.white.setStroke()
            arc.stroke()
        }
    }
}
