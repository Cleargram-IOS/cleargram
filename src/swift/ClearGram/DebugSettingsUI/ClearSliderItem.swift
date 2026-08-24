import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import ItemListUI
import TelegramPresentationData
import PresentationDataUtils

// A settings row with a horizontal slider for an Int32 value: `title` on the left, the formatted
// current value on the right, a slider spanning the row below them.
//
// The control is a system `UISlider` rather than a hand-drawn one: on iOS 26 it picks up the native
// (liquid-glass) slider look for free, so the row matches the `.glass` switches and disclosure rows
// around it. UISlider is a UIControl, so the list yields its pan to it (ListViewScroller refuses to
// start scrolling on a tracking UIControl) — no touch juggling of our own.
//
// UISlider is continuous; discrete steps are snapped in code. The value label follows the snapped
// value live, while the thumb rides free and settles onto the step only when the finger lifts. The
// shared-data write happens once, on release (`finished`), not on every tick.
final class ClearSliderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let value: Int32
    let minValue: Int32
    let maxValue: Int32
    let step: Int32
    let isEnabled: Bool
    let format: (Int32) -> String
    let sectionId: ItemListSectionId
    let updated: (Int32, _ finished: Bool) -> Void

    init(theme: PresentationTheme, title: String, value: Int32, minValue: Int32, maxValue: Int32, step: Int32, isEnabled: Bool, format: @escaping (Int32) -> String, sectionId: ItemListSectionId, updated: @escaping (Int32, _ finished: Bool) -> Void) {
        self.theme = theme
        self.title = title
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.isEnabled = isEnabled
        self.format = format
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ClearSliderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))

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
            if let nodeValue = node() as? ClearSliderItemNode {
                let makeLayout = nodeValue.asyncLayout()

                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
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

private final class ClearSliderItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private let titleNode: ImmediateTextNode
    private let valueNode: ImmediateTextNode
    private var sliderView: UISlider?

    private var item: ClearSliderItem?
    private var layoutParams: ListViewItemLayoutParams?
    private var isTracking = false

    private static let contentHeight: CGFloat = 88.0
    private static let sideInset: CGFloat = 16.0

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()

        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.isUserInteractionEnabled = false

        self.valueNode = ImmediateTextNode()
        self.valueNode.maximumNumberOfLines = 1
        self.valueNode.isUserInteractionEnabled = false

        super.init(layerBacked: false)

        self.addSubnode(self.titleNode)
        self.addSubnode(self.valueNode)
    }

    override func didLoad() {
        super.didLoad()

        let sliderView = UISlider()
        // At the minimum position the thumb sits near the screen's left edge, where a drag right
        // would otherwise be claimed by the navigation's interactive-pop gesture and pop the screen.
        // Stock slider rows opt out of it the same way.
        sliderView.disablesInteractiveTransitionGestureRecognizer = true
        sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        sliderView.addTarget(self, action: #selector(self.sliderInteractionBegan), for: [.touchDown])
        sliderView.addTarget(self, action: #selector(self.sliderInteractionEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        self.view.addSubview(sliderView)
        self.sliderView = sliderView

        if let item = self.item, let params = self.layoutParams {
            self.updateControls(item: item, params: params)
        }
    }

    private func snap(_ raw: Float, item: ClearSliderItem) -> Int32 {
        let stepped = ((raw - Float(item.minValue)) / Float(max(1, item.step))).rounded()
        let value = item.minValue + Int32(stepped) * max(1, item.step)
        return min(item.maxValue, max(item.minValue, value))
    }

    private func setValueLabel(_ value: Int32, item: ClearSliderItem) {
        let color = item.isEnabled ? item.theme.list.itemSecondaryTextColor : item.theme.list.itemDisabledTextColor
        self.valueNode.attributedText = NSAttributedString(string: item.format(value), font: Font.regular(17.0), textColor: color)
        if let params = self.layoutParams {
            self.layoutText(params: params)
        }
    }

    @objc private func sliderInteractionBegan() {
        self.isTracking = true
    }

    @objc private func sliderValueChanged() {
        guard let item = self.item, let sliderView = self.sliderView else {
            return
        }
        let value = self.snap(sliderView.value, item: item)
        self.setValueLabel(value, item: item)
        item.updated(value, false)
    }

    @objc private func sliderInteractionEnded() {
        guard let item = self.item, let sliderView = self.sliderView else {
            self.isTracking = false
            return
        }
        self.isTracking = false
        let value = self.snap(sliderView.value, item: item)
        sliderView.setValue(Float(value), animated: true)
        self.setValueLabel(value, item: item)
        item.updated(value, true)
    }

    private func layoutText(params: ListViewItemLayoutParams) {
        let leftInset = params.leftInset + ClearSliderItemNode.sideInset
        let rightInset = params.rightInset + ClearSliderItemNode.sideInset
        let available = max(1.0, params.width - leftInset - rightInset)

        let valueSize = self.valueNode.updateLayout(CGSize(width: available, height: 44.0))
        let titleSize = self.titleNode.updateLayout(CGSize(width: max(1.0, available - valueSize.width - 8.0), height: 44.0))

        let textTop: CGFloat = 12.0
        self.titleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: textTop), size: titleSize)
        self.valueNode.frame = CGRect(origin: CGPoint(x: params.width - rightInset - valueSize.width, y: textTop), size: valueSize)
    }

    private func updateControls(item: ClearSliderItem, params: ListViewItemLayoutParams) {
        self.titleNode.attributedText = NSAttributedString(
            string: item.title,
            font: Font.regular(17.0),
            textColor: item.isEnabled ? item.theme.list.itemPrimaryTextColor : item.theme.list.itemDisabledTextColor
        )
        self.setValueLabel(item.value, item: item)
        self.layoutText(params: params)

        guard let sliderView = self.sliderView else {
            return
        }
        let leftInset = params.leftInset + ClearSliderItemNode.sideInset
        let rightInset = params.rightInset + ClearSliderItemNode.sideInset
        sliderView.frame = CGRect(
            origin: CGPoint(x: leftInset, y: 44.0),
            size: CGSize(width: max(1.0, params.width - leftInset - rightInset), height: 33.0)
        )
        sliderView.minimumValue = Float(item.minValue)
        sliderView.maximumValue = Float(max(item.minValue + 1, item.maxValue))
        sliderView.isEnabled = item.isEnabled
        sliderView.minimumTrackTintColor = item.theme.list.itemAccentColor
        // Don't fight the finger: while dragging, the thumb is the user's, not the model's.
        if !self.isTracking {
            let value = min(item.maxValue, max(item.minValue, item.value))
            sliderView.setValue(Float(value), animated: false)
        }
    }

    func asyncLayout() -> (_ item: ClearSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let contentSize = CGSize(width: params.width, height: ClearSliderItemNode.contentHeight)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)

            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.item = item
                strongSelf.layoutParams = params

                strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                }
                if strongSelf.topStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                }
                if strongSelf.bottomStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                }
                if strongSelf.maskNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    strongSelf.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }

                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil

                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))

                strongSelf.updateControls(item: item, params: params)
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
