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
    case privacy = 0
    case messages = 1
    case contextMenu = 2
    case profile = 3
    case interface = 4
    case other = 5
}

private enum ClearSettingsEntry: ItemListNodeEntry {
    case hideStories(PresentationTheme, Bool)
    case hideAiFeatures(PresentationTheme, Bool)
    case hidePhoneInSettings(PresentationTheme, Bool)
    case secondsInMessages(PresentationTheme, Bool)
    case doubleTapToEdit(PresentationTheme, Bool)
    case doubleTapDelay(PresentationTheme, Int32)
    case hideContextMenuReply(PresentationTheme, Bool)
    case hideContextMenuPin(PresentationTheme, Bool)
    case hideContextMenuForward(PresentationTheme, Bool)
    case hideContextMenuReport(PresentationTheme, Bool)
    case hideContextMenuSelect(PresentationTheme, Bool)
    case showProfileId(PresentationTheme, Bool)
    case showDC(PresentationTheme, Bool)
    case confirmCalls(PresentationTheme, Bool)
    case animationSpeed(PresentationTheme, Double)
    case defaultEmojisFirst(PresentationTheme, Bool)
    case disableScrollToNextChannel(PresentationTheme, Bool)
    case showInlineReactions(PresentationTheme, Bool)
    case blockCloudDrafts(PresentationTheme, Bool)
    case showForwardedTime(PresentationTheme, Bool)
    case noSelectionCap(PresentationTheme, Bool)
    case stripTrackingParams(PresentationTheme, Bool)
    case replacePreviewLinks(PresentationTheme, Bool)
    case confirmInternalLinks(PresentationTheme, Bool)
    case biometricConfirmation(PresentationTheme, Bool)
    case hideSponsoredMessages(PresentationTheme, Bool)
    case hideStarReactionButton(PresentationTheme, Bool)
    case hideStarReactionCount(PresentationTheme, Bool)
    case hideSimilarChannels(PresentationTheme, Bool)
    case warnPollsRevote(PresentationTheme, Bool)
    case showPackOwner(PresentationTheme, Bool)
    case timeOnServiceMessages(PresentationTheme, Bool)
    case showTabNames(PresentationTheme, Bool)
    case compactChatList(PresentationTheme, Bool)
    case compactFolderNames(PresentationTheme, Bool)
    case allChatsHidden(PresentationTheme, Bool)
    case hideTabBar(PresentationTheme, Bool)
    case wideTabBar(PresentationTheme, Bool)
    case tabBarSearchEnabled(PresentationTheme, Bool)
    case wideChannelPosts(PresentationTheme, Bool)
    case hideChannelBottomButton(PresentationTheme, Bool)
    case disableGalleryCamera(PresentationTheme, Bool)
    case disableGalleryCameraPreview(PresentationTheme, Bool)
    case disableStoryCameraSwipe(PresentationTheme, Bool)
    case enableMultiColumnLayout(PresentationTheme, Bool)
    case flatStickerCorners(PresentationTheme, Bool)
    case saveStickerToPhotos(PresentationTheme, Bool)
    case collapseLongMessages(PresentationTheme, Bool)

    var section: ItemListSectionId {
        switch self {
        case .hideStories, .hideAiFeatures, .hidePhoneInSettings, .biometricConfirmation, .hideSponsoredMessages, .hideSimilarChannels:
            return ClearSettingsSection.privacy.rawValue
        case .secondsInMessages, .doubleTapToEdit, .doubleTapDelay, .disableScrollToNextChannel, .showInlineReactions, .blockCloudDrafts, .showForwardedTime, .timeOnServiceMessages, .warnPollsRevote:
            return ClearSettingsSection.messages.rawValue
        case .hideContextMenuReply, .hideContextMenuPin, .hideContextMenuForward, .hideContextMenuReport, .hideContextMenuSelect:
            return ClearSettingsSection.contextMenu.rawValue
        case .showProfileId, .showDC, .showPackOwner:
            return ClearSettingsSection.profile.rawValue
        case .confirmCalls, .animationSpeed, .defaultEmojisFirst, .stripTrackingParams, .replacePreviewLinks, .confirmInternalLinks, .noSelectionCap, .hideStarReactionButton, .hideStarReactionCount:
            return ClearSettingsSection.other.rawValue
        case .showTabNames, .compactChatList, .compactFolderNames, .allChatsHidden, .hideTabBar, .wideTabBar, .tabBarSearchEnabled, .wideChannelPosts, .hideChannelBottomButton, .disableGalleryCamera, .disableGalleryCameraPreview, .disableStoryCameraSwipe, .enableMultiColumnLayout, .flatStickerCorners, .saveStickerToPhotos, .collapseLongMessages:
            return ClearSettingsSection.interface.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .hideStories: return 1
        case .hideAiFeatures: return 2
        case .hidePhoneInSettings: return 3
        case .biometricConfirmation: return 4
        case .hideSponsoredMessages: return 5
        case .hideSimilarChannels: return 6
        case .secondsInMessages: return 10
        case .doubleTapToEdit: return 11
        case .doubleTapDelay: return 12
        case .disableScrollToNextChannel: return 13
        case .showInlineReactions: return 14
        case .blockCloudDrafts: return 15
        case .showForwardedTime: return 16
        case .timeOnServiceMessages: return 17
        case .warnPollsRevote: return 18
        case .hideContextMenuReply: return 20
        case .hideContextMenuPin: return 21
        case .hideContextMenuForward: return 22
        case .hideContextMenuReport: return 23
        case .hideContextMenuSelect: return 24
        case .showProfileId: return 30
        case .showDC: return 31
        case .showPackOwner: return 32
        case .confirmCalls: return 40
        case .animationSpeed: return 41
        case .defaultEmojisFirst: return 42
        case .stripTrackingParams: return 43
        case .replacePreviewLinks: return 44
        case .confirmInternalLinks: return 45
        case .noSelectionCap: return 46
        case .hideStarReactionButton: return 47
        case .hideStarReactionCount: return 48
        case .showTabNames: return 50
        case .compactChatList: return 51
        case .compactFolderNames: return 52
        case .allChatsHidden: return 53
        case .hideTabBar: return 54
        case .wideTabBar: return 55
        case .tabBarSearchEnabled: return 56
        case .wideChannelPosts: return 57
        case .hideChannelBottomButton: return 58
        case .disableGalleryCamera: return 59
        case .disableGalleryCameraPreview: return 60
        case .disableStoryCameraSwipe: return 61
        case .enableMultiColumnLayout: return 62
        case .flatStickerCorners: return 63
        case .saveStickerToPhotos: return 64
        case .collapseLongMessages: return 65
        }
    }

    static func < (lhs: ClearSettingsEntry, rhs: ClearSettingsEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: ClearSettingsEntry, rhs: ClearSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.hideStories(lt, lv), .hideStories(rt, rv)): return lt === rt && lv == rv
        case let (.hideAiFeatures(lt, lv), .hideAiFeatures(rt, rv)): return lt === rt && lv == rv
        case let (.hidePhoneInSettings(lt, lv), .hidePhoneInSettings(rt, rv)): return lt === rt && lv == rv
        case let (.secondsInMessages(lt, lv), .secondsInMessages(rt, rv)): return lt === rt && lv == rv
        case let (.confirmCalls(lt, lv), .confirmCalls(rt, rv)): return lt === rt && lv == rv
        case let (.doubleTapToEdit(lt, lv), .doubleTapToEdit(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuReply(lt, lv), .hideContextMenuReply(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuPin(lt, lv), .hideContextMenuPin(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuForward(lt, lv), .hideContextMenuForward(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuReport(lt, lv), .hideContextMenuReport(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuSelect(lt, lv), .hideContextMenuSelect(rt, rv)): return lt === rt && lv == rv
        case let (.showProfileId(lt, lv), .showProfileId(rt, rv)): return lt === rt && lv == rv
        case let (.showDC(lt, lv), .showDC(rt, rv)): return lt === rt && lv == rv
        case let (.doubleTapDelay(lt, lv), .doubleTapDelay(rt, rv)): return lt === rt && lv == rv
        case let (.animationSpeed(lt, lv), .animationSpeed(rt, rv)): return lt === rt && lv == rv
        case let (.defaultEmojisFirst(lt, lv), .defaultEmojisFirst(rt, rv)): return lt === rt && lv == rv
        case let (.disableScrollToNextChannel(lt, lv), .disableScrollToNextChannel(rt, rv)): return lt === rt && lv == rv
        case let (.showInlineReactions(lt, lv), .showInlineReactions(rt, rv)): return lt === rt && lv == rv
        case let (.blockCloudDrafts(lt, lv), .blockCloudDrafts(rt, rv)): return lt === rt && lv == rv
        case let (.showForwardedTime(lt, lv), .showForwardedTime(rt, rv)): return lt === rt && lv == rv
        case let (.noSelectionCap(lt, lv), .noSelectionCap(rt, rv)): return lt === rt && lv == rv
        case let (.stripTrackingParams(lt, lv), .stripTrackingParams(rt, rv)): return lt === rt && lv == rv
        case let (.replacePreviewLinks(lt, lv), .replacePreviewLinks(rt, rv)): return lt === rt && lv == rv
        case let (.confirmInternalLinks(lt, lv), .confirmInternalLinks(rt, rv)): return lt === rt && lv == rv
        case let (.biometricConfirmation(lt, lv), .biometricConfirmation(rt, rv)): return lt === rt && lv == rv
        case let (.hideSponsoredMessages(lt, lv), .hideSponsoredMessages(rt, rv)): return lt === rt && lv == rv
        case let (.hideStarReactionButton(lt, lv), .hideStarReactionButton(rt, rv)): return lt === rt && lv == rv
        case let (.hideStarReactionCount(lt, lv), .hideStarReactionCount(rt, rv)): return lt === rt && lv == rv
        case let (.hideSimilarChannels(lt, lv), .hideSimilarChannels(rt, rv)): return lt === rt && lv == rv
        case let (.warnPollsRevote(lt, lv), .warnPollsRevote(rt, rv)): return lt === rt && lv == rv
        case let (.showPackOwner(lt, lv), .showPackOwner(rt, rv)): return lt === rt && lv == rv
        case let (.timeOnServiceMessages(lt, lv), .timeOnServiceMessages(rt, rv)): return lt === rt && lv == rv
        case let (.showTabNames(lt, lv), .showTabNames(rt, rv)): return lt === rt && lv == rv
        case let (.compactChatList(lt, lv), .compactChatList(rt, rv)): return lt === rt && lv == rv
        case let (.compactFolderNames(lt, lv), .compactFolderNames(rt, rv)): return lt === rt && lv == rv
        case let (.allChatsHidden(lt, lv), .allChatsHidden(rt, rv)): return lt === rt && lv == rv
        case let (.hideTabBar(lt, lv), .hideTabBar(rt, rv)): return lt === rt && lv == rv
        case let (.wideTabBar(lt, lv), .wideTabBar(rt, rv)): return lt === rt && lv == rv
        case let (.tabBarSearchEnabled(lt, lv), .tabBarSearchEnabled(rt, rv)): return lt === rt && lv == rv
        case let (.wideChannelPosts(lt, lv), .wideChannelPosts(rt, rv)): return lt === rt && lv == rv
        case let (.hideChannelBottomButton(lt, lv), .hideChannelBottomButton(rt, rv)): return lt === rt && lv == rv
        case let (.disableGalleryCamera(lt, lv), .disableGalleryCamera(rt, rv)): return lt === rt && lv == rv
        case let (.disableGalleryCameraPreview(lt, lv), .disableGalleryCameraPreview(rt, rv)): return lt === rt && lv == rv
        case let (.disableStoryCameraSwipe(lt, lv), .disableStoryCameraSwipe(rt, rv)): return lt === rt && lv == rv
        case let (.enableMultiColumnLayout(lt, lv), .enableMultiColumnLayout(rt, rv)): return lt === rt && lv == rv
        case let (.flatStickerCorners(lt, lv), .flatStickerCorners(rt, rv)): return lt === rt && lv == rv
        case let (.saveStickerToPhotos(lt, lv), .saveStickerToPhotos(rt, rv)): return lt === rt && lv == rv
        case let (.collapseLongMessages(lt, lv), .collapseLongMessages(rt, rv)): return lt === rt && lv == rv
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
        case let .hidePhoneInSettings(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Phone in My Profile", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHidePhoneInSettings(value)
            })
        case let .secondsInMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Seconds in Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateSecondsInMessages(value)
            })
        case let .doubleTapToEdit(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Double Tap to Edit", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDoubleTapToEdit(value)
            })
        case let .doubleTapDelay(_, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Double Tap Delay", label: "\(value) ms", sectionId: self.section, style: .blocks, action: {
                args.editDoubleTapDelay()
            })
        case let .hideContextMenuReply(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Reply", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideContextMenuReply(value)
            })
        case let .hideContextMenuPin(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Pin", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideContextMenuPin(value)
            })
        case let .hideContextMenuForward(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Forward", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideContextMenuForward(value)
            })
        case let .hideContextMenuReport(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Report", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideContextMenuReport(value)
            })
        case let .hideContextMenuSelect(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Select", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideContextMenuSelect(value)
            })
        case let .showProfileId(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Profile ID", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowProfileId(value)
            })
        case let .showDC(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Datacenter", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowDC(value)
            })
        case let .confirmCalls(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Calls", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateConfirmCalls(value)
            })
        case let .animationSpeed(_, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Animation Speed", label: String(format: "%.1fx", value), sectionId: self.section, style: .blocks, action: {
                args.editAnimationSpeed()
            })
        case let .defaultEmojisFirst(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Default Emojis First", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDefaultEmojisFirst(value)
            })
        case let .disableScrollToNextChannel(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Scroll to Next Channel", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableScrollToNextChannel(value)
            })
        case let .showInlineReactions(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Inline Reactions", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowInlineReactions(value)
            })
        case let .blockCloudDrafts(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Block Cloud Drafts", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateBlockCloudDrafts(value)
            })
        case let .showForwardedTime(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Forwarded Time", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowForwardedTime(value)
            })
        case let .noSelectionCap(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "No Selection Cap (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .stripTrackingParams(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Strip Tracking Params (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .replacePreviewLinks(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Replace Preview Links (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .confirmInternalLinks(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Internal Links (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .biometricConfirmation(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Biometric Confirmation (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hideSponsoredMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Sponsored Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideSponsoredMessages(value)
            })
        case let .hideStarReactionButton(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Star Reaction Button (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hideStarReactionCount(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Star Reaction Count (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hideSimilarChannels(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Similar Channels (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .warnPollsRevote(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Warn Polls Revote (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .showPackOwner(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Pack Owner (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .timeOnServiceMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Time on Service Messages (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .showTabNames(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Tab Names (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .compactChatList(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Compact Chat List (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .compactFolderNames(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Compact Folder Names (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .allChatsHidden(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide All Chats Folder (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hideTabBar(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Tab Bar (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .wideTabBar(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Wide Tab Bar (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .tabBarSearchEnabled(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Tab Bar Search (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .wideChannelPosts(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Wide Channel Posts (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hideChannelBottomButton(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Channel Bottom Button (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .disableGalleryCamera(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Gallery Camera", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableGalleryCamera(value)
            })
        case let .disableGalleryCameraPreview(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Gallery Camera Preview (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .disableStoryCameraSwipe(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Story Camera Swipe", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableStoryCameraSwipe(value)
            })
        case let .enableMultiColumnLayout(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Enable Multi-Column Layout (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .flatStickerCorners(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Flat Sticker Corners", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateFlatStickerCorners(value)
            })
        case let .saveStickerToPhotos(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Sticker to Photos", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateSaveStickerToPhotos(value)
            })
        case let .collapseLongMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Collapse Long Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateCollapseLongMessages(value)
            })
        }
    }
}

private struct ClearSettingsArguments {
    let context: AccountContext
    let updateHideStories: (Bool) -> Void
    let updateHideAiFeatures: (Bool) -> Void
    let updateHidePhoneInSettings: (Bool) -> Void
    let updateSecondsInMessages: (Bool) -> Void
    let updateDoubleTapToEdit: (Bool) -> Void
    let updateHideContextMenuReply: (Bool) -> Void
    let updateHideContextMenuPin: (Bool) -> Void
    let updateHideContextMenuForward: (Bool) -> Void
    let updateHideContextMenuReport: (Bool) -> Void
    let updateHideContextMenuSelect: (Bool) -> Void
    let updateShowProfileId: (Bool) -> Void
    let updateShowDC: (Bool) -> Void
    let updateConfirmCalls: (Bool) -> Void
    let updateDefaultEmojisFirst: (Bool) -> Void
    let updateDisableScrollToNextChannel: (Bool) -> Void
    let updateShowInlineReactions: (Bool) -> Void
    let updateHideSponsoredMessages: (Bool) -> Void
    let updateDisableGalleryCamera: (Bool) -> Void
    let updateDisableStoryCameraSwipe: (Bool) -> Void
    let updateFlatStickerCorners: (Bool) -> Void
    let updateSaveStickerToPhotos: (Bool) -> Void
    let updateCollapseLongMessages: (Bool) -> Void
    let updateShowForwardedTime: (Bool) -> Void
    let updateBlockCloudDrafts: (Bool) -> Void
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
        updateHidePhoneInSettings: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hidePhoneInSettings = value; return s }.start()
        },
        updateSecondsInMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.secondsInMessages = value; return s }.start()
        },
        updateDoubleTapToEdit: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.doubleTapToEdit = value; return s }.start()
        },
        updateHideContextMenuReply: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideContextMenuReply = value; return s }.start()
        },
        updateHideContextMenuPin: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideContextMenuPin = value; return s }.start()
        },
        updateHideContextMenuForward: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideContextMenuForward = value; return s }.start()
        },
        updateHideContextMenuReport: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideContextMenuReport = value; return s }.start()
        },
        updateHideContextMenuSelect: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideContextMenuSelect = value; return s }.start()
        },
        updateShowProfileId: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showProfileId = value; return s }.start()
        },
        updateShowDC: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showDC = value; return s }.start()
        },
        updateConfirmCalls: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.confirmCalls = value; return s }.start()
        },
        updateDefaultEmojisFirst: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.defaultEmojisFirst = value; return s }.start()
        },
        updateDisableScrollToNextChannel: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.disableScrollToNextChannel = value; return s }.start()
        },
        updateShowInlineReactions: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showInlineReactions = value; return s }.start()
        },
        updateHideSponsoredMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideSponsoredMessages = value; return s }.start()
        },
        updateDisableGalleryCamera: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.disableGalleryCamera = value; return s }.start()
        },
        updateDisableStoryCameraSwipe: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.disableStoryCameraSwipe = value; return s }.start()
        },
        updateFlatStickerCorners: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.flatStickerCorners = value; return s }.start()
        },
        updateSaveStickerToPhotos: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.saveStickerToPhotos = value; return s }.start()
        },
        updateCollapseLongMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.collapseLongMessages = value; return s }.start()
        },
        updateShowForwardedTime: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showForwardedTime = value; return s }.start()
        },
        updateBlockCloudDrafts: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.blockCloudDrafts = value; return s }.start()
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
        entries.append(.hidePhoneInSettings(presentationData.theme, settings.hidePhoneInSettings))
        entries.append(.biometricConfirmation(presentationData.theme, settings.biometricConfirmation))
        entries.append(.hideSponsoredMessages(presentationData.theme, settings.hideSponsoredMessages))
        entries.append(.hideSimilarChannels(presentationData.theme, settings.hideSimilarChannels))
        entries.append(.secondsInMessages(presentationData.theme, settings.secondsInMessages))
        entries.append(.doubleTapToEdit(presentationData.theme, settings.doubleTapToEdit))
        entries.append(.doubleTapDelay(presentationData.theme, settings.doubleTapDelay))
        entries.append(.disableScrollToNextChannel(presentationData.theme, settings.disableScrollToNextChannel))
        entries.append(.showInlineReactions(presentationData.theme, settings.showInlineReactions))
        entries.append(.blockCloudDrafts(presentationData.theme, settings.blockCloudDrafts))
        entries.append(.showForwardedTime(presentationData.theme, settings.showForwardedTime))
        entries.append(.timeOnServiceMessages(presentationData.theme, settings.timeOnServiceMessages))
        entries.append(.warnPollsRevote(presentationData.theme, settings.warnPollsRevote))
        entries.append(.hideContextMenuReply(presentationData.theme, settings.hideContextMenuReply))
        entries.append(.hideContextMenuPin(presentationData.theme, settings.hideContextMenuPin))
        entries.append(.hideContextMenuForward(presentationData.theme, settings.hideContextMenuForward))
        entries.append(.hideContextMenuReport(presentationData.theme, settings.hideContextMenuReport))
        entries.append(.hideContextMenuSelect(presentationData.theme, settings.hideContextMenuSelect))
        entries.append(.showProfileId(presentationData.theme, settings.showProfileId))
        entries.append(.showDC(presentationData.theme, settings.showDC))
        entries.append(.showPackOwner(presentationData.theme, settings.showPackOwner))
        entries.append(.confirmCalls(presentationData.theme, settings.confirmCalls))
        entries.append(.animationSpeed(presentationData.theme, settings.animationSpeed))
        entries.append(.defaultEmojisFirst(presentationData.theme, settings.defaultEmojisFirst))
        entries.append(.stripTrackingParams(presentationData.theme, settings.stripTrackingParams))
        entries.append(.replacePreviewLinks(presentationData.theme, settings.replacePreviewLinks))
        entries.append(.confirmInternalLinks(presentationData.theme, settings.confirmInternalLinks))
        entries.append(.noSelectionCap(presentationData.theme, settings.noSelectionCap))
        entries.append(.hideStarReactionButton(presentationData.theme, settings.hideStarReactionButton))
        entries.append(.hideStarReactionCount(presentationData.theme, settings.hideStarReactionCount))
        entries.append(.showTabNames(presentationData.theme, settings.showTabNames))
        entries.append(.compactChatList(presentationData.theme, settings.compactChatList))
        entries.append(.compactFolderNames(presentationData.theme, settings.compactFolderNames))
        entries.append(.allChatsHidden(presentationData.theme, settings.allChatsHidden))
        entries.append(.hideTabBar(presentationData.theme, settings.hideTabBar))
        entries.append(.wideTabBar(presentationData.theme, settings.wideTabBar))
        entries.append(.tabBarSearchEnabled(presentationData.theme, settings.tabBarSearchEnabled))
        entries.append(.wideChannelPosts(presentationData.theme, settings.wideChannelPosts))
        entries.append(.hideChannelBottomButton(presentationData.theme, settings.hideChannelBottomButton))
        entries.append(.disableGalleryCamera(presentationData.theme, settings.disableGalleryCamera))
        entries.append(.disableGalleryCameraPreview(presentationData.theme, settings.disableGalleryCameraPreview))
        entries.append(.disableStoryCameraSwipe(presentationData.theme, settings.disableStoryCameraSwipe))
        entries.append(.enableMultiColumnLayout(presentationData.theme, settings.enableMultiColumnLayout))
        entries.append(.flatStickerCorners(presentationData.theme, settings.flatStickerCorners))
        entries.append(.saveStickerToPhotos(presentationData.theme, settings.saveStickerToPhotos))
        entries.append(.collapseLongMessages(presentationData.theme, settings.collapseLongMessages))
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
