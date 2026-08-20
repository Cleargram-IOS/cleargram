import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

// The equalizer screen, reached from the music player's speed menu.
//
// The audio side is `ClearEqualizer` in TelegramCore; this file is the ten faders plus a preamp,
// a preset picker and the plumbing that gets a dragged value into the audio unit before it has
// been written to disk. Dragging calls `ClearEqualizer.update` on every frame — that is what the
// currently playing track hears — and only the end of the drag is persisted through `ClearConfig`.
//
// Same shorthand as the other fork screens: English source text first, Russian second.
private func L(_ en: String, _ ru: String) -> String {
    return ClearStrings.tr(en, ru)
}

// MARK: - Presets

private struct ClearEqualizerPreset {
    let title: String
    // Tenths of a decibel, one per band, in `ClearEqualizer.bandFrequencies` order.
    let gains: [Int32]

    // Boosting a band pushes the signal towards the output unit's ceiling, so a preset that
    // boosts pulls the same amount back out of the preamp. Without it "Bass Booster" on a track
    // that is already mastered loud is not bassier, it is clipped.
    var preamp: Int32 {
        return -max(0, self.gains.max() ?? 0)
    }
}

//                                          32   64  125  250  500   1k   2k   4k   8k  16k
private func clearEqualizerPresets() -> [ClearEqualizerPreset] {
    return [
        ClearEqualizerPreset(title: L("Flat", "Ровно"),
                             gains: [  0,   0,   0,   0,   0,   0,   0,   0,   0,   0]),
        ClearEqualizerPreset(title: L("Bass Booster", "Усиление баса"),
                             gains: [ 60,  50,  40,  20,   0,   0,   0,   0,   0,   0]),
        ClearEqualizerPreset(title: L("Bass Reducer", "Ослабление баса"),
                             gains: [-60, -50, -40, -20,   0,   0,   0,   0,   0,   0]),
        ClearEqualizerPreset(title: L("Treble Booster", "Усиление высоких"),
                             gains: [  0,   0,   0,   0,   0,  10,  30,  40,  50,  60]),
        ClearEqualizerPreset(title: L("Treble Reducer", "Ослабление высоких"),
                             gains: [  0,   0,   0,   0,   0, -10, -30, -40, -50, -60]),
        ClearEqualizerPreset(title: L("Vocal Boost", "Голос"),
                             gains: [-20, -30, -20,  10,  40,  40,  30,  10, -10, -20]),
        ClearEqualizerPreset(title: L("Loudness", "Тонкомпенсация"),
                             gains: [ 60,  40,  10,   0, -20,   0,   0, -20,  40,  50]),
        ClearEqualizerPreset(title: L("Rock", "Рок"),
                             gains: [ 50,  40,  30,  10,   0, -10,  10,  30,  40,  50]),
        ClearEqualizerPreset(title: L("Pop", "Поп"),
                             gains: [-20, -10,   0,  20,  40,  40,  20,   0, -10, -20]),
        ClearEqualizerPreset(title: L("Dance", "Танцевальная"),
                             gains: [ 50,  40,  20,   0,  20,  30,  40,  30,  20,   0]),
        ClearEqualizerPreset(title: L("Electronic", "Электронная"),
                             gains: [ 40,  30,  10,   0, -20,  20,  10,  20,  40,  50]),
        ClearEqualizerPreset(title: L("Hip-Hop", "Хип-хоп"),
                             gains: [ 50,  40,  20,  20, -10, -10,  20, -10,  20,  30]),
        ClearEqualizerPreset(title: L("Jazz", "Джаз"),
                             gains: [ 40,  30,  20,  20, -20, -20,   0,  10,  30,  40]),
        ClearEqualizerPreset(title: L("Classical", "Классика"),
                             gains: [ 40,  30,  20,  10, -20, -20,   0,  20,  30,  40]),
        ClearEqualizerPreset(title: L("Acoustic", "Акустика"),
                             gains: [ 50,  50,  40,  10,  20,  10,  30,  40,  30,  20]),
        ClearEqualizerPreset(title: L("Spoken Word", "Речь"),
                             gains: [-40, -30, -10,  20,  40,  40,  30,  20,   0, -20])
    ]
}

// The label on the preset row. Preamp is deliberately left out of the match: a preset sets one,
// but nudging it afterwards does not make the tone curve stop being "Rock".
private func clearEqualizerPresetName(_ gains: [Int32]) -> String {
    let normalized = ClearEqualizer.State(enabled: true, preamp: 0, gains: gains).normalizedGains
    for preset in clearEqualizerPresets() where preset.gains == normalized {
        return preset.title
    }
    return L("Custom", "Свой")
}

// MARK: - The fader strip

// One control for the whole strip: a preamp fader, a divider, then one fader per band.
//
// It is a `UIControl` on purpose. `ListViewScroller.gestureRecognizerShouldBegin` refuses to start
// the list's pan when the touch landed on a `UIControl` that is already tracking — which is the
// only reason a vertical drag inside a vertically scrolling list can work at all.
//
// While tracking, the view is its own source of truth: the item node stops pushing values into it,
// so a settings signal arriving mid-drag cannot yank a fader out from under the finger.
private final class ClearEqualizerStripView: UIControl {
    private static let topInset: CGFloat = 14.0
    private static let valueLabelHeight: CGFloat = 14.0
    private static let valueLabelGap: CGFloat = 8.0
    private static let trackHeight: CGFloat = 140.0
    private static let bandLabelGap: CGFloat = 10.0
    private static let bandLabelHeight: CGFloat = 14.0
    private static let bottomInset: CGFloat = 14.0

    static let contentHeight: CGFloat = topInset + valueLabelHeight + valueLabelGap + trackHeight + bandLabelGap + bandLabelHeight + bottomInset

    // The preamp is set apart from the bands by a gap rather than by a rule.
    private static let preampGap: CGFloat = 14.0
    private static let trackWidth: CGFloat = 3.0

    // [0] is the preamp, [1...] are the bands.
    private(set) var values: [Int32] = Array(repeating: 0, count: ClearEqualizer.bandCount + 1)
    private var theme: PresentationTheme?
    private var activeIndex: Int?

    var valuesUpdated: ((_ values: [Int32], _ finished: Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .clear
        self.isOpaque = false
        self.contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(theme: PresentationTheme, values: [Int32]) {
        // A drag in progress owns the values; anything arriving from the settings signal in the
        // meantime is the echo of what this very drag already wrote.
        if !self.isTracking {
            self.values = values
        }
        self.theme = theme
        self.setNeedsDisplay()
    }

    // MARK: Geometry

    private var columnCount: Int {
        return ClearEqualizer.bandCount + 1
    }

    private var columnWidth: CGFloat {
        return (self.bounds.width - ClearEqualizerStripView.preampGap) / CGFloat(self.columnCount)
    }

    private func columnOrigin(_ index: Int) -> CGFloat {
        return CGFloat(index) * self.columnWidth + (index == 0 ? 0.0 : ClearEqualizerStripView.preampGap)
    }

    private func columnCenter(_ index: Int) -> CGFloat {
        return self.columnOrigin(index) + self.columnWidth / 2.0
    }

    private var knobDiameter: CGFloat {
        return max(12.0, min(17.0, self.columnWidth * 0.55))
    }

    private var trackTop: CGFloat {
        return ClearEqualizerStripView.topInset + ClearEqualizerStripView.valueLabelHeight + ClearEqualizerStripView.valueLabelGap
    }

    // The knob travels between its own centres, not between the ends of the track, so at ±12 dB
    // it sits flush inside the track instead of hanging off it.
    private var travel: (top: CGFloat, height: CGFloat) {
        let radius = self.knobDiameter / 2.0
        return (self.trackTop + radius, ClearEqualizerStripView.trackHeight - radius * 2.0)
    }

    private func valueY(_ value: Int32) -> CGFloat {
        let limit = CGFloat(ClearEqualizer.gainLimit)
        let fraction = (CGFloat(ClearEqualizer.clampGain(value)) + limit) / (limit * 2.0)
        let travel = self.travel
        return travel.top + travel.height * (1.0 - fraction)
    }

    private func value(atY y: CGFloat) -> Int32 {
        let limit = CGFloat(ClearEqualizer.gainLimit)
        let travel = self.travel
        let fraction = max(0.0, min(1.0, 1.0 - (y - travel.top) / travel.height))
        let raw = fraction * limit * 2.0 - limit
        // Whole decibels: finer steps are not audible on an octave band, and they would make the
        // readouts four characters wide in a column that is barely wider than three.
        return Int32((raw / 10.0).rounded()) * 10
    }

    private func columnIndex(atX x: CGFloat) -> Int? {
        guard self.bounds.width > 0.0 else {
            return nil
        }
        for index in 0 ..< self.columnCount {
            // The bands are contiguous, so a band's right edge is the next band's left edge; the
            // preamp is the exception, and the gap it is separated by is split down the middle.
            let edge = self.columnOrigin(index) + self.columnWidth + (index == 0 ? ClearEqualizerStripView.preampGap / 2.0 : 0.0)
            if x < edge {
                return index
            }
        }
        return self.columnCount - 1
    }

    // MARK: Tracking

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let index = self.columnIndex(atX: touch.location(in: self).x) else {
            return false
        }
        self.activeIndex = index
        self.apply(touch: touch, finished: false)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.apply(touch: touch, finished: false)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch {
            self.apply(touch: touch, finished: true)
        } else {
            self.valuesUpdated?(self.values, true)
        }
        self.activeIndex = nil
        self.setNeedsDisplay()
    }

    override func cancelTracking(with event: UIEvent?) {
        self.activeIndex = nil
        self.valuesUpdated?(self.values, true)
        self.setNeedsDisplay()
    }

    // The column is chosen when the finger lands and kept for the rest of the drag, so sliding
    // sideways past a neighbour cannot drag two faders at once.
    private func apply(touch: UITouch, finished: Bool) {
        guard let index = self.activeIndex, index < self.values.count else {
            return
        }
        let updated = self.value(atY: touch.location(in: self).y)
        if self.values[index] != updated {
            self.values[index] = updated
            self.setNeedsDisplay()
            self.valuesUpdated?(self.values, finished)
        } else if finished {
            self.valuesUpdated?(self.values, true)
        }
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let theme = self.theme, let context = UIGraphicsGetCurrentContext(), self.bounds.width > 0.0 else {
            return
        }

        let accent = theme.list.itemAccentColor
        let muted = theme.list.itemSecondaryTextColor
        let trackTop = self.trackTop
        let trackHeight = ClearEqualizerStripView.trackHeight
        let trackWidth = ClearEqualizerStripView.trackWidth
        let zeroY = self.valueY(0)
        let knobDiameter = self.knobDiameter

        // The 0 dB reference. Barely there on purpose: at rest the knobs line up on it anyway,
        // and it is only needed once some of them have moved off it.
        context.setFillColor(muted.withMultipliedAlpha(0.12).cgColor)
        context.fill(CGRect(x: 0.0, y: zeroY - UIScreenPixel / 2.0, width: self.bounds.width, height: UIScreenPixel))

        for index in 0 ..< self.columnCount {
            let center = self.columnCenter(index)
            let value = index < self.values.count ? self.values[index] : 0
            let knobY = self.valueY(value)
            let isActive = self.activeIndex == index

            context.setFillColor(muted.withMultipliedAlpha(0.2).cgColor)
            let track = CGRect(x: center - trackWidth / 2.0, y: trackTop, width: trackWidth, height: trackHeight)
            context.addPath(UIBezierPath(roundedRect: track, cornerRadius: trackWidth / 2.0).cgPath)
            context.fillPath()

            // Filled from 0 dB rather than from the bottom: on an equalizer what matters is the
            // distance from flat, in whichever direction.
            if value != 0 {
                context.setFillColor(accent.cgColor)
                let fill = CGRect(x: track.minX, y: min(zeroY, knobY), width: trackWidth, height: abs(knobY - zeroY))
                context.addPath(UIBezierPath(roundedRect: fill, cornerRadius: trackWidth / 2.0).cgPath)
                context.fillPath()
            }

            // Grows a little under the finger, so the knob being dragged is the one you can see.
            let diameter = isActive ? knobDiameter + 3.0 : knobDiameter
            context.setFillColor(accent.cgColor)
            context.fillEllipse(in: CGRect(x: center - diameter / 2.0, y: knobY - diameter / 2.0, width: diameter, height: diameter))

            // Readouts only where there is something to read: at rest the row is empty rather
            // than eleven zeroes.
            if value != 0 || isActive {
                self.drawLabel(
                    ClearEqualizer.formatGain(value, withUnit: false),
                    centeredAt: center,
                    top: ClearEqualizerStripView.topInset,
                    height: ClearEqualizerStripView.valueLabelHeight,
                    font: isActive ? Font.semibold(11.0) : Font.regular(11.0),
                    color: isActive ? accent : muted
                )
            }

            let bandTitle = index == 0 ? L("Pre", "Пре") : ClearEqualizer.formatFrequency(ClearEqualizer.bandFrequencies[index - 1])
            self.drawLabel(
                bandTitle,
                centeredAt: center,
                top: trackTop + trackHeight + ClearEqualizerStripView.bandLabelGap,
                height: ClearEqualizerStripView.bandLabelHeight,
                font: Font.regular(11.0),
                color: muted
            )
        }
    }

    private func drawLabel(_ text: String, centeredAt x: CGFloat, top: CGFloat, height: CGFloat, font: UIFont, color: UIColor) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.boundingRect(with: CGSize(width: 200.0, height: height), options: [.usesLineFragmentOrigin], context: nil).size
        string.draw(at: CGPoint(x: x - size.width / 2.0, y: top + (height - size.height) / 2.0))
    }
}

private final class ClearEqualizerBandsItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    // [0] preamp, [1...] bands — the same shape the strip view uses.
    let values: [Int32]
    let sectionId: ItemListSectionId
    let updated: (_ values: [Int32], _ finished: Bool) -> Void

    init(theme: PresentationTheme, values: [Int32], sectionId: ItemListSectionId, updated: @escaping (_ values: [Int32], _ finished: Bool) -> Void) {
        self.theme = theme
        self.values = values
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ClearEqualizerBandsItemNode()
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
            if let nodeValue = node() as? ClearEqualizerBandsItemNode {
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

private final class ClearEqualizerBandsItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private var stripView: ClearEqualizerStripView?

    private var item: ClearEqualizerBandsItem?
    private var layoutParams: ListViewItemLayoutParams?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()

        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()

        let stripView = ClearEqualizerStripView()
        stripView.valuesUpdated = { [weak self] values, finished in
            self?.item?.updated(values, finished)
        }
        self.view.addSubview(stripView)
        self.stripView = stripView

        if let item = self.item, let params = self.layoutParams {
            self.updateStrip(item: item, params: params)
        }
    }

    private func updateStrip(item: ClearEqualizerBandsItem, params: ListViewItemLayoutParams) {
        guard let stripView = self.stripView else {
            return
        }
        let sideInset = params.leftInset + 16.0
        stripView.frame = CGRect(
            origin: CGPoint(x: sideInset, y: 0.0),
            size: CGSize(width: max(1.0, params.width - sideInset - params.rightInset - 16.0), height: ClearEqualizerStripView.contentHeight)
        )
        stripView.update(theme: item.theme, values: item.values)
    }

    func asyncLayout() -> (_ item: ClearEqualizerBandsItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let contentSize = CGSize(width: params.width, height: ClearEqualizerStripView.contentHeight)
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

                strongSelf.updateStrip(item: item, params: params)
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

// MARK: - Entries

private enum ClearEqualizerSection: ItemListSectionId {
    case bands = 0
    case preset = 1
    case reset = 2
}

private enum ClearEqualizerEntry: ItemListNodeEntry {
    case bands(values: [Int32])
    case preset(title: String, label: String)
    case reset(title: String, enabled: Bool)

    var section: ItemListSectionId {
        switch self {
        case .bands:
            return ClearEqualizerSection.bands.rawValue
        case .preset:
            return ClearEqualizerSection.preset.rawValue
        case .reset:
            return ClearEqualizerSection.reset.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .bands:
            return 0
        case .preset:
            return 1
        case .reset:
            return 2
        }
    }

    static func <(lhs: ClearEqualizerEntry, rhs: ClearEqualizerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    // Spelled out rather than synthesized: the conformance is inherited through
    // ItemListNodeEntry, and the other fork screens declare theirs the same way.
    static func ==(lhs: ClearEqualizerEntry, rhs: ClearEqualizerEntry) -> Bool {
        switch lhs {
        case let .bands(values):
            if case .bands(values) = rhs {
                return true
            }
            return false
        case let .preset(title, label):
            if case .preset(title, label) = rhs {
                return true
            }
            return false
        case let .reset(title, enabled):
            if case .reset(title, enabled) = rhs {
                return true
            }
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearEqualizerArguments
        switch self {
        case let .bands(values):
            return ClearEqualizerBandsItem(
                theme: presentationData.theme,
                values: values,
                sectionId: self.section,
                updated: { values, finished in
                    args.setValues(values, finished)
                }
            )
        case let .preset(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.pickPreset()
                }
            )
        case let .reset(title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.reset()
                }
            )
        }
    }
}

private final class ClearEqualizerArguments {
    let setValues: (_ values: [Int32], _ finished: Bool) -> Void
    let pickPreset: () -> Void
    let reset: () -> Void

    init(
        setValues: @escaping (_ values: [Int32], _ finished: Bool) -> Void,
        pickPreset: @escaping () -> Void,
        reset: @escaping () -> Void
    ) {
        self.setValues = setValues
        self.pickPreset = pickPreset
        self.reset = reset
    }
}

// MARK: - Controller

public func clearEqualizerController(context: AccountContext) -> ViewController {
    let accountManager = context.sharedContext.accountManager

    var presentImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    // The screen writes through both paths at once: `ClearEqualizer.update` so the track playing
    // right now hears the change, and `ClearConfig.update` so it survives the screen. Persisting
    // is deliberately left to the end of a drag — a shared-data transaction per touch-move frame
    // is not something to put on the main queue.
    let persist: (ClearEqualizer.State) -> Void = { state in
        let _ = ClearConfig.update(accountManager: accountManager) { settings in
            var updated = settings
            updated.equalizerEnabled = state.enabled
            updated.equalizerPreamp = ClearEqualizer.clampGain(state.preamp)
            // A flat curve is stored as an empty list: it is what a fresh install looks like, and
            // it keeps an exported `.cleargram` from carrying ten zeroes nobody changed.
            let normalized = state.normalizedGains
            updated.equalizerGains = normalized.allSatisfy({ $0 == 0 }) ? [] : normalized
            return updated
        }.start()
    }

    let arguments = ClearEqualizerArguments(
        setValues: { values, finished in
            guard !values.isEmpty else {
                return
            }
            let state = ClearEqualizer.State(
                enabled: ClearEqualizer.current().enabled,
                preamp: values[0],
                gains: Array(values.dropFirst())
            )
            ClearEqualizer.update(state)
            if finished {
                persist(state)
            }
        },
        pickPreset: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetButtonItem] = []
            for preset in clearEqualizerPresets() {
                items.append(ActionSheetButtonItem(title: preset.title, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    let state = ClearEqualizer.State(enabled: ClearEqualizer.current().enabled, preamp: preset.preamp, gains: preset.gains)
                    ClearEqualizer.update(state)
                    persist(state)
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentImpl?(actionSheet)
        },
        reset: {
            let state = ClearEqualizer.State(enabled: ClearEqualizer.current().enabled, preamp: 0, gains: [])
            ClearEqualizer.update(state)
            persist(state)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        clearConfigEntry(accountManager: accountManager)
    )
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let itemListPresentationData = ItemListPresentationData(presentationData)
        let state = ClearConfig.equalizerState(settings)
        let gains = state.normalizedGains

        var entries: [ClearEqualizerEntry] = []
        entries.append(.bands(values: [ClearEqualizer.clampGain(state.preamp)] + gains))

        entries.append(.preset(title: L("Preset", "Пресет"), label: clearEqualizerPresetName(state.gains)))
        entries.append(.reset(title: L("Reset to Flat", "Сбросить"), enabled: !state.isFlat))

        let controllerState = ItemListControllerState(
            presentationData: itemListPresentationData,
            title: .text(L("Equalizer", "Эквалайзер")),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                dismissImpl?()
            }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: itemListPresentationData,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }

    return controller
}
