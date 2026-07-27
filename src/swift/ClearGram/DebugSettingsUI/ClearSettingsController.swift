import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

private enum ClearSettingsSection: ItemListSectionId {
    case general = 0
    case chat = 1
}

private enum ClearSettingsEntry: ItemListNodeEntry {
    case hideStories(PresentationTheme, Bool)
    case hideAiFeatures(PresentationTheme, Bool)
    case doubleTapDelay(PresentationTheme, Int32)
    case animationSpeed(PresentationTheme, Double)

    var section: ItemListSectionId {
        switch self {
        case .hideStories, .hideAiFeatures:
            return ClearSettingsSection.general.rawValue
        case .doubleTapDelay, .animationSpeed:
            return ClearSettingsSection.chat.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .hideStories: return 1
        case .hideAiFeatures: return 2
        case .doubleTapDelay: return 100
        case .animationSpeed: return 101
        }
    }

    static func < (lhs: ClearSettingsEntry, rhs: ClearSettingsEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: ClearSettingsEntry, rhs: ClearSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.hideStories(lt, lv), .hideStories(rt, rv)): return lt === rt && lv == rv
        case let (.hideAiFeatures(lt, lv), .hideAiFeatures(rt, rv)): return lt === rt && lv == rv
        case let (.doubleTapDelay(lt, lv), .doubleTapDelay(rt, rv)): return lt === rt && lv == rv
        case let (.animationSpeed(lt, lv), .animationSpeed(rt, rv)): return lt === rt && lv == rv
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearSettingsArguments
        switch self {
        case let .hideStories(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideStories(value)
            })
        case let .hideAiFeatures(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide AI Features", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideAiFeatures(value)
            })
        case let .doubleTapDelay(_, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Double Tap Delay", label: "\(value) ms", sectionId: self.section, style: .blocks, action: {
                args.editDoubleTapDelay()
            })
        case let .animationSpeed(_, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Animation Speed", label: String(format: "%.1fx", value), sectionId: self.section, style: .blocks, action: {
                args.editAnimationSpeed()
            })
        }
    }
}

private struct ClearSettingsArguments {
    let context: AccountContext
    let updateHideStories: (Bool) -> Void
    let updateHideAiFeatures: (Bool) -> Void
    let editDoubleTapDelay: () -> Void
    let editAnimationSpeed: () -> Void
}

public func clearSettingsController(context: AccountContext) -> ViewController {
    var editDoubleTapDelayImpl: (() -> Void)?
    var editAnimationSpeedImpl: (() -> Void)?

    let arguments = ClearSettingsArguments(
        context: context,
        updateHideStories: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideStories = value; return s }.start()
        },
        updateHideAiFeatures: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideAiFeatures = value; return s }.start()
        },
        editDoubleTapDelay: { editDoubleTapDelayImpl?() },
        editAnimationSpeed: { editAnimationSpeedImpl?() }
    )

    let settingsSignal = clearConfigEntry(accountManager: context.sharedContext.accountManager)

    let signal = combineLatest(context.sharedContext.presentationData, settingsSignal)
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let pd = ItemListPresentationData(presentationData)
        var entries: [ClearSettingsEntry] = []
        entries.append(.hideStories(presentationData.theme, settings.hideStories))
        entries.append(.hideAiFeatures(presentationData.theme, settings.hideAiFeatures))
        entries.append(.doubleTapDelay(presentationData.theme, settings.doubleTapDelay))
        entries.append(.animationSpeed(presentationData.theme, settings.animationSpeed))
        let state = ItemListControllerState(presentationData: pd, title: .text("Cleargram Settings"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: pd, entries: entries, style: .blocks, animateChanges: true), arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    editDoubleTapDelayImpl = { [weak controller] in
        guard let controller else { return }
        let alert = UIAlertController(title: "Double Tap Delay", message: "Milliseconds between taps", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "300"
            tf.keyboardType = .numberPad
            tf.text = "\(ClearConfig.doubleTapDelay)"
        }
        alert.addAction(UIAlertAction(title: "Set", style: .default) { _ in
            if let text = alert.textFields?.first?.text, let value = Int32(text) {
                let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.doubleTapDelay = value; return s }.start()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        controller.present(alert, animated: true)
    }

    editAnimationSpeedImpl = { [weak controller] in
        guard let controller else { return }
        let alert = UIAlertController(title: "Animation Speed", message: "Multiplier (1.0 = normal, 0.5 = half speed)", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "1.0"
            tf.keyboardType = .decimalPad
            tf.text = String(format: "%.1f", ClearConfig.animationSpeed)
        }
        alert.addAction(UIAlertAction(title: "Set", style: .default) { _ in
            if let text = alert.textFields?.first?.text, let value = Double(text) {
                let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.animationSpeed = value; return s }.start()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        controller.present(alert, animated: true)
    }

    return controller
}
