import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

// The pre-26 tab bar: full width, flush with the bottom edge, no pill.
//
// It is not a reconstruction — `TabBarNode` is still in the tree, untouched since 2024; the
// redesign simply stopped constructing it and routed `TabBarControllerNode` through
// `TabBarComponent` instead. This wrapper owns that node and reproduces the layout the deleted
// half of `TabBarContollerNode.swift` used to do around it (`ebcd0557e5^`), so the stock file
// only needs a guard per call site rather than a second implementation inline.
//
// Two things had to be bridged to hook the old node back up:
//
//   * **The toolbar.** The chat-list edit mode ("Read All", "Delete") is drawn by the glass
//     `GlassControlPanelComponent` now; the old bar used `ToolbarNode`, which is still in
//     `Display`. Legacy mode uses `ToolbarNode`, full width over the tab bar, as before.
//   * **The context-menu type.** `TabBarNode` hands its long-press a
//     `ContextExtractedContentContainingNode`, while `ViewController.tabBarItemContextAction`
//     now takes a `ContextExtractedContentContainingView`. There is no conversion between the
//     two, but every override (chat list, calls, contacts, settings) passes it on as
//     `.reference(…)` and reads nothing from it but `contentView`, whose *frame* is all
//     `ContextControllerExtractedPresentationNode` converts to screen space. So the bridge is a
//     frame: one empty, non-interactive containing view parked over the pressed tab. Anything
//     that starts reading more than the frame off that view will need a real conversion.
final class ClearLegacyTabBar {
    let node: TabBarNode

    private var theme: PresentationTheme
    private let toolbarActionSelected: (ToolbarActionOption) -> Void
    private var toolbarNode: ToolbarNode?

    private weak var disabledOverlay: ASDisplayNode?

    // Reused across presses; see the note above on why an empty view is enough.
    private let contextSourceBridge: ContextExtractedContentContainingView

    init(
        theme: PresentationTheme,
        itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void,
        contextAction: @escaping (Int, ContextExtractedContentContainingView, ContextGesture) -> Void,
        swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void,
        toolbarActionSelected: @escaping (ToolbarActionOption) -> Void
    ) {
        self.theme = theme
        self.toolbarActionSelected = toolbarActionSelected

        self.contextSourceBridge = ContextExtractedContentContainingView(frame: CGRect())
        self.contextSourceBridge.isUserInteractionEnabled = false
        self.contextSourceBridge.isHidden = true

        var contextActionImpl: ((Int, ContextExtractedContentContainingNode, ContextGesture) -> Void)? = nil
        self.node = TabBarNode(theme: theme, itemSelected: itemSelected, contextAction: { index, sourceNode, gesture in
            contextActionImpl?(index, sourceNode, gesture)
        }, swipeAction: swipeAction)

        contextActionImpl = { [weak self] index, sourceNode, gesture in
            guard let self else {
                return
            }
            contextAction(index, self.bridgedContextSource(for: sourceNode), gesture)
        }
    }

    func attach(to container: ASDisplayNode, disabledOverlay: ASDisplayNode) {
        self.disabledOverlay = disabledOverlay
        container.addSubnode(self.node)
        container.addSubnode(disabledOverlay)
    }

    // The stock node re-inserts the current controller's node underneath on every switch.
    func bringToFront(in view: UIView) {
        view.bringSubviewToFront(self.node.view)
        if let disabledOverlay = self.disabledOverlay {
            view.bringSubviewToFront(disabledOverlay.view)
        }
        if let toolbarNode = self.toolbarNode {
            view.bringSubviewToFront(toolbarNode.view)
        }
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.node.updateTheme(theme)
        self.toolbarNode?.updateTheme(ToolbarTheme(rootControllerTheme: theme))
    }

    func frameForItem(at index: Int) -> CGRect? {
        guard index >= 0 && index < self.node.tabBarItems.count else {
            return nil
        }
        guard let itemFrame = self.node.frameForControllerTab(at: index) else {
            return nil
        }
        return self.node.view.convert(itemFrame, to: self.node.view.superview)
    }

    func isPointInsideContentArea(point: CGPoint) -> Bool {
        return point.y < self.node.frame.minY
    }

    /// Lays the bar out and returns the inset it occupies at the bottom of `layout`, which is what
    /// `TabBarControllerNode.containerLayoutUpdated` hands back to the current controller.
    func update(
        layout: ContainerViewLayout,
        toolbar: Toolbar?,
        items: [TabBarNodeItem],
        selectedIndex: Int,
        isTabBarHidden: Bool,
        transition: ContainedViewLayoutTransition
    ) -> CGFloat {
        // Assigning `tabBarItems` rebuilds every item node, and this runs on each layout pass.
        if !self.node.tabBarItems.elementsEqual(items, by: { $0 === $1 }) {
            self.node.tabBarItems = items
        }
        self.node.selectedIndex = selectedIndex < items.count ? selectedIndex : nil

        var options: ContainerViewLayoutInsetOptions = []
        if layout.metrics.widthClass == .regular {
            options.insert(.input)
        }
        let bottomInset: CGFloat = layout.insets(options: options).bottom
        // A non-zero left safe inset means landscape with a notch, where the bar goes short.
        let tabBarHeight: CGFloat = (layout.safeInsets.left.isZero ? 49.0 : 34.0) + bottomInset

        let tabBarFrame = CGRect(
            origin: CGPoint(x: 0.0, y: layout.size.height - (isTabBarHidden ? 0.0 : tabBarHeight)),
            size: CGSize(width: layout.size.width, height: tabBarHeight)
        )

        transition.updateFrame(node: self.node, frame: tabBarFrame)
        self.node.updateLayout(size: tabBarFrame.size, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right, additionalSideInsets: layout.additionalInsets, bottomInset: bottomInset, transition: transition)

        if let disabledOverlay = self.disabledOverlay {
            transition.updateFrame(node: disabledOverlay, frame: tabBarFrame)
        }

        self.updateToolbar(toolbar, frame: tabBarFrame, layout: layout, bottomInset: bottomInset, transition: transition)

        return layout.size.height - tabBarFrame.minY
    }

    private func updateToolbar(_ toolbar: Toolbar?, frame: CGRect, layout: ContainerViewLayout, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let toolbar else {
            if let toolbarNode = self.toolbarNode {
                self.toolbarNode = nil
                transition.updateAlpha(node: toolbarNode, alpha: 0.0, completion: { [weak toolbarNode] _ in
                    toolbarNode?.removeFromSupernode()
                })
            }
            return
        }

        if let toolbarNode = self.toolbarNode {
            transition.updateFrame(node: toolbarNode, frame: frame)
            toolbarNode.updateLayout(size: frame.size, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right, additionalSideInsets: layout.additionalInsets, bottomInset: bottomInset, toolbar: toolbar, transition: transition)
        } else {
            let toolbarNode = ToolbarNode(theme: ToolbarTheme(rootControllerTheme: self.theme), displaySeparator: true, left: { [weak self] in
                self?.toolbarActionSelected(.left)
            }, right: { [weak self] in
                self?.toolbarActionSelected(.right)
            }, middle: { [weak self] in
                self?.toolbarActionSelected(.middle)
            })
            toolbarNode.frame = frame
            toolbarNode.updateLayout(size: frame.size, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right, additionalSideInsets: layout.additionalInsets, bottomInset: bottomInset, toolbar: toolbar, transition: .immediate)
            self.node.supernode?.addSubnode(toolbarNode)
            self.toolbarNode = toolbarNode
            if transition.isAnimated {
                toolbarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }
        }
    }

    private func bridgedContextSource(for sourceNode: ContextExtractedContentContainingNode) -> ContextExtractedContentContainingView {
        let contentView = sourceNode.contentNode.view
        if self.contextSourceBridge.superview !== contentView {
            self.contextSourceBridge.removeFromSuperview()
            contentView.addSubview(self.contextSourceBridge)
        }
        self.contextSourceBridge.frame = CGRect(origin: CGPoint(), size: contentView.bounds.size)
        self.contextSourceBridge.contentView.frame = CGRect(origin: CGPoint(), size: contentView.bounds.size)
        return self.contextSourceBridge
    }
}
