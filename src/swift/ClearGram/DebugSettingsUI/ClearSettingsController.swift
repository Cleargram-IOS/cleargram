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
import UndoUI

private enum ClearSettingsSection: ItemListSectionId {
    case chatList = 0
    case tabBar = 1
    case chat = 2
    case messages = 3
    case links = 4
    case contextMenu = 5
    case profile = 6
    case media = 7
    case privacy = 8
    case reset = 9
}

private enum ClearSettingsEntry: ItemListNodeEntry {
    case compactChatList(PresentationTheme, Bool)
    case compactFolderNames(PresentationTheme, Bool)
    case allChatsHidden(PresentationTheme, Bool)
    case hideTabBar(PresentationTheme, Bool)
    case showTabNames(PresentationTheme, Bool, Bool)
    case wideTabBar(PresentationTheme, Bool, Bool)
    case tabBarSearchEnabled(PresentationTheme, Bool, Bool)
    case wideChannelPosts(PresentationTheme, Bool)
    case hideChannelBottomButton(PresentationTheme, Bool)
    case disableScrollToNextChannel(PresentationTheme, Bool)
    case hideStarReactionButton(PresentationTheme, Bool)
    case hideStarReactionCount(PresentationTheme, Bool)
    case collapseLongMessages(PresentationTheme, Bool)
    case disableContactsTab(PresentationTheme, Bool)
    case disableCallsButton(PresentationTheme, Bool)
    case showAudioFormatBitrate(PresentationTheme, Bool)
    case allChatsTitleLengthOverride(PresentationTheme, Bool)
    case fontSizeOverride(PresentationTheme, Bool)
    case searchByUserId(PresentationTheme, Bool)
    case adminLogsImprovements(PresentationTheme, Bool)
    case paranoiaMode(PresentationTheme, Bool)
    case showChannelPostAuthor(PresentationTheme, Bool)
    case hideChannelJoinRequests(PresentationTheme, Bool)
    case fasterFileLoad(PresentationTheme, Bool)
    case videoCircleAudioSource(PresentationTheme, Bool)
    case videoQualityOriginalToggle(PresentationTheme, Bool)
    case sendVideoAsCircle(PresentationTheme, Bool)
    case hidePremiumStarsGifts(PresentationTheme, Bool)
    case fakeGlass(PresentationTheme, Bool)
    case forceClearGlass(PresentationTheme, Bool)
    case showForwardedTime(PresentationTheme, Bool)
    case timeOnServiceMessages(PresentationTheme, Bool)
    case secondsInMessages(PresentationTheme, Bool)
    case doubleTapToEdit(PresentationTheme, Bool)
    case blockCloudDrafts(PresentationTheme, Bool)
    case warnPollsRevote(PresentationTheme, Bool)
    case stripTrackingParams(PresentationTheme, Bool)
    case replacePreviewLinks(PresentationTheme, Bool)
    case confirmInternalLinks(PresentationTheme, Bool)
    case hideContextMenuReply(PresentationTheme, Bool)
    case hideContextMenuPin(PresentationTheme, Bool)
    case hideContextMenuForward(PresentationTheme, Bool)
    case hideContextMenuReport(PresentationTheme, Bool)
    case hideContextMenuSelect(PresentationTheme, Bool)
    case showProfileId(PresentationTheme, Bool)
    case showDC(PresentationTheme, Bool)
    case showPackOwner(PresentationTheme, Bool)
    case hidePhoneInSettings(PresentationTheme, Bool)
    case disableGalleryCamera(PresentationTheme, Bool)
    case disableStoryCameraSwipe(PresentationTheme, Bool)
    case flatStickerCorners(PresentationTheme, Bool)
    case saveStickerToPhotos(PresentationTheme, Bool)
    case hideStories(PresentationTheme, Bool)
    case hideAiFeatures(PresentationTheme, Bool)
    case hideSponsoredMessages(PresentationTheme, Bool)
    case hideSimilarChannels(PresentationTheme, Bool)
    case confirmCalls(PresentationTheme, Bool)
    case biometricConfirmDeleteChat(PresentationTheme, Bool)
    case biometricConfirmClearHistory(PresentationTheme, Bool)
    case biometricConfirmLogout(PresentationTheme, Bool)
    case defaultEmojisFirst(PresentationTheme, Bool)
    case resetSettings(PresentationTheme)

    var section: ItemListSectionId {
        switch self {
        case .compactChatList, .compactFolderNames, .allChatsHidden, .allChatsTitleLengthOverride:
            return ClearSettingsSection.chatList.rawValue
        case .hideTabBar, .showTabNames, .wideTabBar, .tabBarSearchEnabled, .disableContactsTab, .disableCallsButton:
            return ClearSettingsSection.tabBar.rawValue
        case .wideChannelPosts, .hideChannelBottomButton, .disableScrollToNextChannel, .hideStarReactionButton, .hideStarReactionCount, .collapseLongMessages, .showForwardedTime, .timeOnServiceMessages, .fontSizeOverride:
            return ClearSettingsSection.chat.rawValue
        case .secondsInMessages, .doubleTapToEdit, .blockCloudDrafts, .warnPollsRevote:
            return ClearSettingsSection.messages.rawValue
        case .stripTrackingParams, .replacePreviewLinks, .confirmInternalLinks:
            return ClearSettingsSection.links.rawValue
        case .hideContextMenuReply, .hideContextMenuPin, .hideContextMenuForward, .hideContextMenuReport, .hideContextMenuSelect:
            return ClearSettingsSection.contextMenu.rawValue
        case .showProfileId, .showDC, .showPackOwner, .hidePhoneInSettings:
            return ClearSettingsSection.profile.rawValue
        case .disableGalleryCamera, .disableStoryCameraSwipe, .flatStickerCorners, .saveStickerToPhotos, .showAudioFormatBitrate, .fasterFileLoad, .videoCircleAudioSource, .videoQualityOriginalToggle, .sendVideoAsCircle:
            return ClearSettingsSection.media.rawValue
        case .hideStories, .hideAiFeatures, .hideSponsoredMessages, .hideSimilarChannels, .confirmCalls, .biometricConfirmDeleteChat, .biometricConfirmClearHistory, .biometricConfirmLogout, .defaultEmojisFirst, .fakeGlass, .forceClearGlass, .searchByUserId, .adminLogsImprovements, .paranoiaMode, .showChannelPostAuthor, .hideChannelJoinRequests, .hidePremiumStarsGifts:
            return ClearSettingsSection.privacy.rawValue
        case .resetSettings:
            return ClearSettingsSection.reset.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .compactChatList: return 1
        case .compactFolderNames: return 2
        case .allChatsHidden: return 3
        case .hideTabBar: return 10
        case .showTabNames: return 11
        case .wideTabBar: return 12
        case .tabBarSearchEnabled: return 13
        case .wideChannelPosts: return 20
        case .hideChannelBottomButton: return 21
        case .disableScrollToNextChannel: return 22
        // case .showInlineReactions: return 23
        case .hideStarReactionButton: return 24
        case .hideStarReactionCount: return 25
        case .collapseLongMessages: return 26
        case .showForwardedTime: return 27
        case .timeOnServiceMessages: return 28
        case .secondsInMessages: return 30
        case .doubleTapToEdit: return 31
        case .blockCloudDrafts: return 33
        case .warnPollsRevote: return 34
        case .stripTrackingParams: return 40
        case .replacePreviewLinks: return 41
        case .confirmInternalLinks: return 42
        case .hideContextMenuReply: return 50
        case .hideContextMenuPin: return 51
        case .hideContextMenuForward: return 52
        case .hideContextMenuReport: return 53
        case .hideContextMenuSelect: return 54
        case .showProfileId: return 60
        case .showDC: return 61
        case .showPackOwner: return 62
        case .hidePhoneInSettings: return 63
        case .disableGalleryCamera: return 70
        case .disableStoryCameraSwipe: return 72
        case .flatStickerCorners: return 73
        case .saveStickerToPhotos: return 74
        case .showAudioFormatBitrate: return 75
        case .fasterFileLoad: return 76
        case .videoCircleAudioSource: return 77
        case .videoQualityOriginalToggle: return 78
        case .sendVideoAsCircle: return 79
        case .hideStories: return 80
        case .hideAiFeatures: return 81
        case .hideSponsoredMessages: return 82
        case .hideSimilarChannels: return 83
        case .confirmCalls: return 84
        case .biometricConfirmDeleteChat: return 841
        case .biometricConfirmClearHistory: return 842
        case .biometricConfirmLogout: return 843
        case .defaultEmojisFirst: return 86
        case .fakeGlass: return 88
        case .forceClearGlass: return 89
        case .searchByUserId: return 90
        case .adminLogsImprovements: return 91
        case .paranoiaMode: return 92
        case .showChannelPostAuthor: return 93
        case .hideChannelJoinRequests: return 94
        case .hidePremiumStarsGifts: return 95
        case .allChatsTitleLengthOverride: return 96
        case .fontSizeOverride: return 97
        case .disableContactsTab: return 14
        case .disableCallsButton: return 15
        case .resetSettings: return 99
        }
    }

    static func < (lhs: ClearSettingsEntry, rhs: ClearSettingsEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: ClearSettingsEntry, rhs: ClearSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.compactChatList(lt, lv), .compactChatList(rt, rv)): return lt === rt && lv == rv
        case let (.compactFolderNames(lt, lv), .compactFolderNames(rt, rv)): return lt === rt && lv == rv
        case let (.allChatsHidden(lt, lv), .allChatsHidden(rt, rv)): return lt === rt && lv == rv
        case let (.hideTabBar(lt, lv), .hideTabBar(rt, rv)): return lt === rt && lv == rv
        case let (.showTabNames(lt, lv, lh), .showTabNames(rt, rv, rh)): return lt === rt && lv == rv && lh == rh
        case let (.wideTabBar(lt, lv, lh), .wideTabBar(rt, rv, rh)): return lt === rt && lv == rv && lh == rh
        case let (.tabBarSearchEnabled(lt, lv, lh), .tabBarSearchEnabled(rt, rv, rh)): return lt === rt && lv == rv && lh == rh
        case let (.wideChannelPosts(lt, lv), .wideChannelPosts(rt, rv)): return lt === rt && lv == rv
        case let (.hideChannelBottomButton(lt, lv), .hideChannelBottomButton(rt, rv)): return lt === rt && lv == rv
        case let (.disableScrollToNextChannel(lt, lv), .disableScrollToNextChannel(rt, rv)): return lt === rt && lv == rv
        case let (.hideStarReactionButton(lt, lv), .hideStarReactionButton(rt, rv)): return lt === rt && lv == rv
        case let (.hideStarReactionCount(lt, lv), .hideStarReactionCount(rt, rv)): return lt === rt && lv == rv
        case let (.collapseLongMessages(lt, lv), .collapseLongMessages(rt, rv)): return lt === rt && lv == rv
        case let (.disableContactsTab(lt, lv), .disableContactsTab(rt, rv)): return lt === rt && lv == rv
        case let (.disableCallsButton(lt, lv), .disableCallsButton(rt, rv)): return lt === rt && lv == rv
        case let (.showAudioFormatBitrate(lt, lv), .showAudioFormatBitrate(rt, rv)): return lt === rt && lv == rv
        case let (.allChatsTitleLengthOverride(lt, lv), .allChatsTitleLengthOverride(rt, rv)): return lt === rt && lv == rv
        case let (.fontSizeOverride(lt, lv), .fontSizeOverride(rt, rv)): return lt === rt && lv == rv
        case let (.searchByUserId(lt, lv), .searchByUserId(rt, rv)): return lt === rt && lv == rv
        case let (.adminLogsImprovements(lt, lv), .adminLogsImprovements(rt, rv)): return lt === rt && lv == rv
        case let (.paranoiaMode(lt, lv), .paranoiaMode(rt, rv)): return lt === rt && lv == rv
        case let (.showChannelPostAuthor(lt, lv), .showChannelPostAuthor(rt, rv)): return lt === rt && lv == rv
        case let (.hideChannelJoinRequests(lt, lv), .hideChannelJoinRequests(rt, rv)): return lt === rt && lv == rv
        case let (.fasterFileLoad(lt, lv), .fasterFileLoad(rt, rv)): return lt === rt && lv == rv
        case let (.videoCircleAudioSource(lt, lv), .videoCircleAudioSource(rt, rv)): return lt === rt && lv == rv
        case let (.videoQualityOriginalToggle(lt, lv), .videoQualityOriginalToggle(rt, rv)): return lt === rt && lv == rv
        case let (.sendVideoAsCircle(lt, lv), .sendVideoAsCircle(rt, rv)): return lt === rt && lv == rv
        case let (.hidePremiumStarsGifts(lt, lv), .hidePremiumStarsGifts(rt, rv)): return lt === rt && lv == rv
        case let (.fakeGlass(lt, lv), .fakeGlass(rt, rv)): return lt === rt && lv == rv
        case let (.forceClearGlass(lt, lv), .forceClearGlass(rt, rv)): return lt === rt && lv == rv
        case let (.showForwardedTime(lt, lv), .showForwardedTime(rt, rv)): return lt === rt && lv == rv
        case let (.timeOnServiceMessages(lt, lv), .timeOnServiceMessages(rt, rv)): return lt === rt && lv == rv
        case let (.secondsInMessages(lt, lv), .secondsInMessages(rt, rv)): return lt === rt && lv == rv
        case let (.doubleTapToEdit(lt, lv), .doubleTapToEdit(rt, rv)): return lt === rt && lv == rv
        case let (.blockCloudDrafts(lt, lv), .blockCloudDrafts(rt, rv)): return lt === rt && lv == rv
        case let (.warnPollsRevote(lt, lv), .warnPollsRevote(rt, rv)): return lt === rt && lv == rv
        case let (.stripTrackingParams(lt, lv), .stripTrackingParams(rt, rv)): return lt === rt && lv == rv
        case let (.replacePreviewLinks(lt, lv), .replacePreviewLinks(rt, rv)): return lt === rt && lv == rv
        case let (.confirmInternalLinks(lt, lv), .confirmInternalLinks(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuReply(lt, lv), .hideContextMenuReply(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuPin(lt, lv), .hideContextMenuPin(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuForward(lt, lv), .hideContextMenuForward(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuReport(lt, lv), .hideContextMenuReport(rt, rv)): return lt === rt && lv == rv
        case let (.hideContextMenuSelect(lt, lv), .hideContextMenuSelect(rt, rv)): return lt === rt && lv == rv
        case let (.showProfileId(lt, lv), .showProfileId(rt, rv)): return lt === rt && lv == rv
        case let (.showDC(lt, lv), .showDC(rt, rv)): return lt === rt && lv == rv
        case let (.showPackOwner(lt, lv), .showPackOwner(rt, rv)): return lt === rt && lv == rv
        case let (.hidePhoneInSettings(lt, lv), .hidePhoneInSettings(rt, rv)): return lt === rt && lv == rv
        case let (.disableGalleryCamera(lt, lv), .disableGalleryCamera(rt, rv)): return lt === rt && lv == rv
        case let (.disableStoryCameraSwipe(lt, lv), .disableStoryCameraSwipe(rt, rv)): return lt === rt && lv == rv
        case let (.flatStickerCorners(lt, lv), .flatStickerCorners(rt, rv)): return lt === rt && lv == rv
        case let (.saveStickerToPhotos(lt, lv), .saveStickerToPhotos(rt, rv)): return lt === rt && lv == rv
        case let (.hideStories(lt, lv), .hideStories(rt, rv)): return lt === rt && lv == rv
        case let (.hideAiFeatures(lt, lv), .hideAiFeatures(rt, rv)): return lt === rt && lv == rv
        case let (.hideSponsoredMessages(lt, lv), .hideSponsoredMessages(rt, rv)): return lt === rt && lv == rv
        case let (.hideSimilarChannels(lt, lv), .hideSimilarChannels(rt, rv)): return lt === rt && lv == rv
        case let (.confirmCalls(lt, lv), .confirmCalls(rt, rv)): return lt === rt && lv == rv
        case let (.biometricConfirmDeleteChat(lt, lv), .biometricConfirmDeleteChat(rt, rv)): return lt === rt && lv == rv
        case let (.biometricConfirmClearHistory(lt, lv), .biometricConfirmClearHistory(rt, rv)): return lt === rt && lv == rv
        case let (.biometricConfirmLogout(lt, lv), .biometricConfirmLogout(rt, rv)): return lt === rt && lv == rv
        case let (.defaultEmojisFirst(lt, lv), .defaultEmojisFirst(rt, rv)): return lt === rt && lv == rv
        case let (.resetSettings(lt), .resetSettings(rt)): return lt === rt
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearSettingsArguments
        switch self {
        case let .compactChatList(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Compact Chat List", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateCompactChatList(value)
            })
        case let .compactFolderNames(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Compact Folder Names", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateCompactFolderNames(value)
            })
        case let .allChatsHidden(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide All Chats Folder", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateAllChatsHidden(value)
            })
        case let .hideTabBar(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Tab Bar", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideTabBar(value)
            })
        case let .showTabNames(_, value, hideTabBar):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Tab Names", value: value, enabled: !hideTabBar, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowTabNames(value)
            })
        case let .wideTabBar(_, value, hideTabBar):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Wide Tab Bar", value: value, enabled: !hideTabBar, sectionId: self.section, style: .blocks, updated: { value in
                args.updateWideTabBar(value)
            })
        case let .tabBarSearchEnabled(_, value, hideTabBar):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Tab Bar Search", value: value, enabled: !hideTabBar, sectionId: self.section, style: .blocks, updated: { value in
                args.updateTabBarSearchEnabled(value)
            })
        case let .wideChannelPosts(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Wide Channel Posts", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateWideChannelPosts(value)
            })
        case let .hideChannelBottomButton(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Channel Bottom Button", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideChannelBottomButton(value)
            })
        case let .disableScrollToNextChannel(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Scroll to Next Channel", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableScrollToNextChannel(value)
            })
        case let .hideStarReactionButton(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Star Reaction Button", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideStarReactionButton(value)
            })
        case let .hideStarReactionCount(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Star Reaction Count", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideStarReactionCount(value)
            })
        case let .collapseLongMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Collapse Long Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateCollapseLongMessages(value)
            })
        case let .fakeGlass(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Fake Glass (Legacy UI)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateFakeGlass(value)
            })
        case let .forceClearGlass(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Force Clear Glass", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateForceClearGlass(value)
            })
        case let .showForwardedTime(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Forwarded Time", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowForwardedTime(value)
            })
        case let .timeOnServiceMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Time on Service Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateTimeOnServiceMessages(value)
            })
        case let .secondsInMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Seconds in Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateSecondsInMessages(value)
            })
        case let .doubleTapToEdit(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Double Tap to Edit", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDoubleTapToEdit(value)
            })
        case let .blockCloudDrafts(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Block Cloud Drafts", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateBlockCloudDrafts(value)
            })
        case let .warnPollsRevote(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Warn Polls Revote", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateWarnPollsRevote(value)
            })
        case let .stripTrackingParams(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Strip Tracking Params", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateStripTrackingParams(value)
            })
        case let .replacePreviewLinks(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Replace Preview Links", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateReplacePreviewLinks(value)
            })
        case let .confirmInternalLinks(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Internal Links", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateConfirmInternalLinks(value)
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
        case let .showPackOwner(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Pack Owner", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowPackOwner(value)
            })
        case let .hidePhoneInSettings(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Phone in My Profile", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHidePhoneInSettings(value)
            })
        case let .disableGalleryCamera(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Gallery Camera", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableGalleryCamera(value)
            })
        case let .disableStoryCameraSwipe(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Story Camera Swipe", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableStoryCameraSwipe(value)
            })
        case let .flatStickerCorners(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Flat Sticker Corners", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateFlatStickerCorners(value)
            })
        case let .saveStickerToPhotos(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Sticker to Photos", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateSaveStickerToPhotos(value)
            })
        case let .hideStories(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideStories(value)
            })
        case let .hideAiFeatures(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide AI Features", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideAiFeatures(value)
            })
        case let .hideSponsoredMessages(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Sponsored Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideSponsoredMessages(value)
            })
        case let .hideSimilarChannels(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Similar Channels", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideSimilarChannels(value)
            })
        case let .confirmCalls(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Calls", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateConfirmCalls(value)
            })
        case let .biometricConfirmDeleteChat(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Biometric Confirm: Delete Chat", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateBiometricConfirmDeleteChat(value)
            })
        case let .biometricConfirmClearHistory(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Biometric Confirm: Clear History", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateBiometricConfirmClearHistory(value)
            })
        case let .biometricConfirmLogout(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Biometric Confirm: Logout", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateBiometricConfirmLogout(value)
            })
        case let .defaultEmojisFirst(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Default Emojis First", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDefaultEmojisFirst(value)
            })
        case let .disableContactsTab(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Contacts Tab", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableContactsTab(value)
            })
        case let .disableCallsButton(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Call Button", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateDisableCallsButton(value)
            })
        case let .showAudioFormatBitrate(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Audio Format & Bitrate", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateShowAudioFormatBitrate(value)
            })
        case let .allChatsTitleLengthOverride(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "All Chats Title Length Override (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .fontSizeOverride(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Font Size Override (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .searchByUserId(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Search by User ID (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .adminLogsImprovements(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Admin Logs Improvements (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .paranoiaMode(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Paranoia Mode (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .showChannelPostAuthor(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Channel Post Author (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hideChannelJoinRequests(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Channel Join Requests", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateHideChannelJoinRequests(value)
            })
        case let .fasterFileLoad(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Faster File Load", value: value, sectionId: self.section, style: .blocks, updated: { value in
                args.updateFasterFileLoad(value)
            })
        case let .videoCircleAudioSource(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Video Circle Audio Source (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .videoQualityOriginalToggle(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Video Quality Original Toggle (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .sendVideoAsCircle(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Send Video as Circle (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case let .hidePremiumStarsGifts(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Premium/Stars/Gifts (soon)", value: value, enabled: false, sectionId: self.section, style: .blocks, updated: { _ in })
        case .resetSettings:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Reset Settings", label: "", sectionId: self.section, style: .blocks, action: {
                args.resetSettings()
            })
        }
    }
}

private struct ClearSettingsArguments {
    let context: AccountContext
    let updateCompactChatList: (Bool) -> Void
    let updateCompactFolderNames: (Bool) -> Void
    let updateAllChatsHidden: (Bool) -> Void
    let updateHideTabBar: (Bool) -> Void
    let updateShowTabNames: (Bool) -> Void
    let updateWideTabBar: (Bool) -> Void
    let updateTabBarSearchEnabled: (Bool) -> Void
    let updateWideChannelPosts: (Bool) -> Void
    let updateHideChannelBottomButton: (Bool) -> Void
    let updateDisableScrollToNextChannel: (Bool) -> Void
    // let updateShowInlineReactions: (Bool) -> Void
    let updateHideStarReactionButton: (Bool) -> Void
    let updateHideStarReactionCount: (Bool) -> Void
    let updateCollapseLongMessages: (Bool) -> Void
    let updateShowForwardedTime: (Bool) -> Void
    let updateTimeOnServiceMessages: (Bool) -> Void
    let updateSecondsInMessages: (Bool) -> Void
    let updateDoubleTapToEdit: (Bool) -> Void
    let updateBlockCloudDrafts: (Bool) -> Void
    let updateWarnPollsRevote: (Bool) -> Void
    let updateStripTrackingParams: (Bool) -> Void
    let updateReplacePreviewLinks: (Bool) -> Void
    let updateConfirmInternalLinks: (Bool) -> Void
    let updateHideContextMenuReply: (Bool) -> Void
    let updateHideContextMenuPin: (Bool) -> Void
    let updateHideContextMenuForward: (Bool) -> Void
    let updateHideContextMenuReport: (Bool) -> Void
    let updateHideContextMenuSelect: (Bool) -> Void
    let updateShowProfileId: (Bool) -> Void
    let updateShowDC: (Bool) -> Void
    let updateShowPackOwner: (Bool) -> Void
    let updateHidePhoneInSettings: (Bool) -> Void
    let updateDisableGalleryCamera: (Bool) -> Void
    let updateDisableStoryCameraSwipe: (Bool) -> Void
    let updateFlatStickerCorners: (Bool) -> Void
    let updateSaveStickerToPhotos: (Bool) -> Void
    let updateShowAudioFormatBitrate: (Bool) -> Void
    let updateHideStories: (Bool) -> Void
    let updateHideAiFeatures: (Bool) -> Void
    let updateHideSponsoredMessages: (Bool) -> Void
    let updateHideSimilarChannels: (Bool) -> Void
    let updateHideChannelJoinRequests: (Bool) -> Void
    let updateFasterFileLoad: (Bool) -> Void
    let updateConfirmCalls: (Bool) -> Void
    let updateBiometricConfirmDeleteChat: (Bool) -> Void
    let updateBiometricConfirmClearHistory: (Bool) -> Void
    let updateBiometricConfirmLogout: (Bool) -> Void
    let updateDefaultEmojisFirst: (Bool) -> Void
    let updateDisableContactsTab: (Bool) -> Void
    let updateDisableCallsButton: (Bool) -> Void
    let updateFakeGlass: (Bool) -> Void
    let updateForceClearGlass: (Bool) -> Void
    let resetSettings: () -> Void
}

public func clearSettingsController(context: AccountContext) -> ViewController {
    var askForRestartImpl: (() -> Void)?

    let arguments = ClearSettingsArguments(
        context: context,
        updateCompactChatList: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.compactChatList = value; return s }.start()
            askForRestartImpl?()
        },
        updateCompactFolderNames: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.compactFolderNames = value; return s }.start()
            askForRestartImpl?()
        },
        updateAllChatsHidden: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.allChatsHidden = value; return s }.start()
            askForRestartImpl?()
        },
        updateHideTabBar: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideTabBar = value; return s }.start()
            askForRestartImpl?()
        },
        updateShowTabNames: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showTabNames = value; return s }.start()
            askForRestartImpl?()
        },
        updateWideTabBar: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.wideTabBar = value; return s }.start()
            askForRestartImpl?()
        },
        updateTabBarSearchEnabled: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.tabBarSearchEnabled = value; return s }.start()
        },
        updateWideChannelPosts: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.wideChannelPosts = value; return s }.start()
        },
        updateHideChannelBottomButton: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideChannelBottomButton = value; return s }.start()
        },
        updateDisableScrollToNextChannel: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.disableScrollToNextChannel = value; return s }.start()
        },
        // updateShowInlineReactions: { value in
        //     let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showInlineReactions = value; return s }.start()
        // },
        updateHideStarReactionButton: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideStarReactionButton = value; return s }.start()
        },
        updateHideStarReactionCount: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideStarReactionCount = value; return s }.start()
        },
        updateCollapseLongMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.collapseLongMessages = value; return s }.start()
        },
        updateShowForwardedTime: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showForwardedTime = value; return s }.start()
        },
        updateTimeOnServiceMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.timeOnServiceMessages = value; return s }.start()
        },
        updateSecondsInMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.secondsInMessages = value; return s }.start()
        },
        updateDoubleTapToEdit: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.doubleTapToEdit = value; return s }.start()
        },
        updateBlockCloudDrafts: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.blockCloudDrafts = value; return s }.start()
        },
        updateWarnPollsRevote: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.warnPollsRevote = value; return s }.start()
        },
        updateStripTrackingParams: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.stripTrackingParams = value; return s }.start()
        },
        updateReplacePreviewLinks: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.replacePreviewLinks = value; return s }.start()
        },
        updateConfirmInternalLinks: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.confirmInternalLinks = value; return s }.start()
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
        updateShowPackOwner: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showPackOwner = value; return s }.start()
        },
        updateHidePhoneInSettings: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hidePhoneInSettings = value; return s }.start()
            askForRestartImpl?()
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
        updateShowAudioFormatBitrate: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.showAudioFormatBitrate = value; return s }.start()
        },
        updateHideStories: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideStories = value; return s }.start()
        },
        updateHideAiFeatures: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideAiFeatures = value; return s }.start()
        },
        updateHideSponsoredMessages: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideSponsoredMessages = value; return s }.start()
        },
        updateHideSimilarChannels: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideSimilarChannels = value; return s }.start()
        },
        updateHideChannelJoinRequests: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.hideChannelJoinRequests = value; return s }.start()
        },
        updateFasterFileLoad: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.fasterFileLoad = value; return s }.start()
        },
        updateConfirmCalls: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.confirmCalls = value; return s }.start()
        },
        updateBiometricConfirmDeleteChat: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.biometricConfirmDeleteChat = value; return s }.start()
        },
        updateBiometricConfirmClearHistory: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.biometricConfirmClearHistory = value; return s }.start()
        },
        updateBiometricConfirmLogout: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.biometricConfirmLogout = value; return s }.start()
        },
        updateDefaultEmojisFirst: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.defaultEmojisFirst = value; return s }.start()
        },
        updateDisableContactsTab: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.disableContactsTab = value; return s }.start()
            askForRestartImpl?()
        },
        updateDisableCallsButton: { value in
            let _ = ClearConfig.update(accountManager: context.sharedContext.accountManager) { var s = $0; s.disableCallsButton = value; return s }.start()
        },
        updateFakeGlass: { value in
            let _ = context.sharedContext.accountManager.transaction { transaction in
                transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings) { settings in
                    var s = settings?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
                    s.fakeGlass = value
                    return EnginePreferencesEntry(s)
                }
            }.start()
        },
        updateForceClearGlass: { value in
            let _ = context.sharedContext.accountManager.transaction { transaction in
                transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings) { settings in
                    var s = settings?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
                    s.forceClearGlass = value
                    return EnginePreferencesEntry(s)
                }
            }.start()
        },
        resetSettings: {
            let _ = ClearConfig.reset(accountManager: context.sharedContext.accountManager).start()
        }
    )

    let settingsSignal = clearConfigEntry(accountManager: context.sharedContext.accountManager)
    let experimentalSignal = context.sharedContext.accountManager.sharedData(keys: Set([ApplicationSpecificSharedDataKeys.experimentalUISettings]))
    |> map { sharedData -> ExperimentalUISettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
    }

    let signal = combineLatest(context.sharedContext.presentationData, settingsSignal, experimentalSignal)
    |> map { presentationData, settings, experimentalSettings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let pd = ItemListPresentationData(presentationData)
        var entries: [ClearSettingsEntry] = []
        entries.append(.compactChatList(presentationData.theme, settings.compactChatList))
        entries.append(.compactFolderNames(presentationData.theme, settings.compactFolderNames))
        entries.append(.allChatsHidden(presentationData.theme, settings.allChatsHidden))
        entries.append(.hideTabBar(presentationData.theme, settings.hideTabBar))
        entries.append(.showTabNames(presentationData.theme, settings.showTabNames, settings.hideTabBar))
        entries.append(.wideTabBar(presentationData.theme, settings.wideTabBar, settings.hideTabBar))
        entries.append(.tabBarSearchEnabled(presentationData.theme, settings.tabBarSearchEnabled, settings.hideTabBar))
        entries.append(.disableContactsTab(presentationData.theme, settings.disableContactsTab))
        entries.append(.disableCallsButton(presentationData.theme, settings.disableCallsButton))
        entries.append(.wideChannelPosts(presentationData.theme, settings.wideChannelPosts))
        entries.append(.hideChannelBottomButton(presentationData.theme, settings.hideChannelBottomButton))
        entries.append(.disableScrollToNextChannel(presentationData.theme, settings.disableScrollToNextChannel))
        // entries.append(.showInlineReactions(presentationData.theme, settings.showInlineReactions))
        entries.append(.hideStarReactionButton(presentationData.theme, settings.hideStarReactionButton))
        entries.append(.hideStarReactionCount(presentationData.theme, settings.hideStarReactionCount))
        entries.append(.collapseLongMessages(presentationData.theme, settings.collapseLongMessages))
        entries.append(.showForwardedTime(presentationData.theme, settings.showForwardedTime))
        entries.append(.timeOnServiceMessages(presentationData.theme, settings.timeOnServiceMessages))
        entries.append(.secondsInMessages(presentationData.theme, settings.secondsInMessages))
        entries.append(.doubleTapToEdit(presentationData.theme, settings.doubleTapToEdit))
        entries.append(.blockCloudDrafts(presentationData.theme, settings.blockCloudDrafts))
        entries.append(.warnPollsRevote(presentationData.theme, settings.warnPollsRevote))
        entries.append(.stripTrackingParams(presentationData.theme, settings.stripTrackingParams))
        entries.append(.replacePreviewLinks(presentationData.theme, settings.replacePreviewLinks))
        entries.append(.confirmInternalLinks(presentationData.theme, settings.confirmInternalLinks))
        entries.append(.hideContextMenuReply(presentationData.theme, settings.hideContextMenuReply))
        entries.append(.hideContextMenuPin(presentationData.theme, settings.hideContextMenuPin))
        entries.append(.hideContextMenuForward(presentationData.theme, settings.hideContextMenuForward))
        entries.append(.hideContextMenuReport(presentationData.theme, settings.hideContextMenuReport))
        entries.append(.hideContextMenuSelect(presentationData.theme, settings.hideContextMenuSelect))
        entries.append(.showProfileId(presentationData.theme, settings.showProfileId))
        entries.append(.showDC(presentationData.theme, settings.showDC))
        entries.append(.showPackOwner(presentationData.theme, settings.showPackOwner))
        entries.append(.hidePhoneInSettings(presentationData.theme, settings.hidePhoneInSettings))
        entries.append(.disableGalleryCamera(presentationData.theme, settings.disableGalleryCamera))
        entries.append(.disableStoryCameraSwipe(presentationData.theme, settings.disableStoryCameraSwipe))
        entries.append(.flatStickerCorners(presentationData.theme, settings.flatStickerCorners))
        entries.append(.saveStickerToPhotos(presentationData.theme, settings.saveStickerToPhotos))
        entries.append(.showAudioFormatBitrate(presentationData.theme, settings.showAudioFormatBitrate))
        entries.append(.fasterFileLoad(presentationData.theme, settings.fasterFileLoad))
        entries.append(.videoCircleAudioSource(presentationData.theme, settings.videoCircleAudioSource))
        entries.append(.videoQualityOriginalToggle(presentationData.theme, settings.videoQualityOriginalToggle))
        entries.append(.sendVideoAsCircle(presentationData.theme, settings.sendVideoAsCircle))
        entries.append(.allChatsTitleLengthOverride(presentationData.theme, settings.allChatsTitleLengthOverride != 0))
        entries.append(.hideStories(presentationData.theme, settings.hideStories))
        entries.append(.hideAiFeatures(presentationData.theme, settings.hideAiFeatures))
        entries.append(.hideSponsoredMessages(presentationData.theme, settings.hideSponsoredMessages))
        entries.append(.hideSimilarChannels(presentationData.theme, settings.hideSimilarChannels))
        entries.append(.confirmCalls(presentationData.theme, settings.confirmCalls))
        entries.append(.biometricConfirmDeleteChat(presentationData.theme, settings.biometricConfirmDeleteChat))
        entries.append(.biometricConfirmClearHistory(presentationData.theme, settings.biometricConfirmClearHistory))
        entries.append(.biometricConfirmLogout(presentationData.theme, settings.biometricConfirmLogout))
        entries.append(.defaultEmojisFirst(presentationData.theme, settings.defaultEmojisFirst))
        entries.append(.fakeGlass(presentationData.theme, experimentalSettings.fakeGlass))
        entries.append(.forceClearGlass(presentationData.theme, experimentalSettings.forceClearGlass))
        entries.append(.searchByUserId(presentationData.theme, settings.searchByUserId))
        entries.append(.adminLogsImprovements(presentationData.theme, settings.adminLogsImprovements))
        entries.append(.paranoiaMode(presentationData.theme, settings.paranoiaMode))
        entries.append(.showChannelPostAuthor(presentationData.theme, settings.showChannelPostAuthor))
        entries.append(.hideChannelJoinRequests(presentationData.theme, settings.hideChannelJoinRequests))
        entries.append(.hidePremiumStarsGifts(presentationData.theme, settings.hidePremiumStarsGifts))
        entries.append(.fontSizeOverride(presentationData.theme, settings.fontSizeOverride))
        entries.append(.resetSettings(presentationData.theme))
        let state = ItemListControllerState(presentationData: pd, title: .text("Cleargram Settings"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: pd, entries: entries, style: .blocks, animateChanges: true), arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    askForRestartImpl = { [weak controller] in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let undoController = UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: "Restart required to apply changes", timeout: nil, customUndoText: "Restart Now"),
            elevatedLayout: false,
            action: { action in
                if action == .undo { exit(0) }
                return true
            }
        )
        controller.present(undoController, in: .current)
    }

    return controller
}
