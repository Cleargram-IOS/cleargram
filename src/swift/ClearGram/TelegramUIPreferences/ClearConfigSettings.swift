import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Centralized fork-config model. Stored under shared-data key 30
// (ApplicationSpecificSharedDataKeys.clearConfigSettings). Synced across devices via
// accountManager, survives logout, reactive via `clearConfigEntry`.
//
// Add new toggles as fields here; expose accessors on `ClearConfig` (the enum facade below).
// Default-off: every behavior change gated by `ClearConfig.<toggle>.value`.

public struct ClearConfigSettings: Codable, Equatable {
    public var hideStories: Bool
    public var hideAiFeatures: Bool
    public var secondsInMessages: Bool
    public var confirmCalls: Bool
    public var doubleTapToEdit: Bool
    public var showProfileId: Bool
    public var showDC: Bool
    public var hidePhoneInSettings: Bool
    public var hideContextMenuReply: Bool
    public var hideContextMenuPin: Bool
    public var hideContextMenuForward: Bool
    public var hideContextMenuReport: Bool
    public var hideContextMenuSelect: Bool
    public var doubleTapDelay: Int32
    public var animationSpeed: Double
    public var defaultEmojisFirst: Bool
    public var disableScrollToNextChannel: Bool
    public var showInlineReactions: Bool
    public var blockCloudDrafts: Bool
    public var showForwardedTime: Bool
    public var noSelectionCap: Bool
    public var stripTrackingParams: Bool
    public var replacePreviewLinks: Bool
    public var confirmInternalLinks: Bool
    public var biometricConfirmation: Bool
    public var hideSponsoredMessages: Bool
    public var hideStarReactionButton: Bool
    public var hideStarReactionCount: Bool
    public var hideSimilarChannels: Bool
    public var warnPollsRevote: Bool
    public var showPackOwner: Bool
    public var timeOnServiceMessages: Bool
    public var showTabNames: Bool
    public var compactChatList: Bool
    public var chatListLines: Int32
    public var compactFolderNames: Bool
    public var allChatsHidden: Bool
    public var hideTabBar: Bool
    public var wideTabBar: Bool
    public var tabBarSearchEnabled: Bool
    public var wideChannelPosts: Bool
    public var hideChannelBottomButton: Bool
    public var disableGalleryCamera: Bool
    public var disableGalleryCameraPreview: Bool
    public var disableStoryCameraSwipe: Bool
    public var enableMultiColumnLayout: Bool
    public var flatStickerCorners: Bool
    public var saveStickerToPhotos: Bool
    public var collapseLongMessages: Bool
    public var showPackOwner: Bool

    public static var defaultSettings: ClearConfigSettings {
        return ClearConfigSettings(
            hideStories: false,
            hideAiFeatures: false,
            secondsInMessages: false,
            confirmCalls: false,
            doubleTapToEdit: false,
            showProfileId: false,
            showDC: false,
            hidePhoneInSettings: false,
            hideContextMenuReply: false,
            hideContextMenuPin: false,
            hideContextMenuForward: false,
            hideContextMenuReport: false,
            hideContextMenuSelect: false,
            doubleTapDelay: 300,
            animationSpeed: 1.0,
            defaultEmojisFirst: false,
            disableScrollToNextChannel: false,
            showInlineReactions: false,
            blockCloudDrafts: false,
            showForwardedTime: false,
            noSelectionCap: false,
            stripTrackingParams: false,
            replacePreviewLinks: false,
            confirmInternalLinks: false,
            biometricConfirmation: false,
            hideSponsoredMessages: false,
            hideStarReactionButton: false,
            hideStarReactionCount: false,
            hideSimilarChannels: false,
            warnPollsRevote: false,
            showPackOwner: false,
            timeOnServiceMessages: false,
            showTabNames: false,
            compactChatList: false,
            chatListLines: 2,
            compactFolderNames: false,
            allChatsHidden: false,
            hideTabBar: false,
            wideTabBar: false,
            tabBarSearchEnabled: false,
            wideChannelPosts: false,
            hideChannelBottomButton: false,
            disableGalleryCamera: false,
            disableGalleryCameraPreview: false,
            disableStoryCameraSwipe: false,
            enableMultiColumnLayout: false,
            flatStickerCorners: false,
            saveStickerToPhotos: false,
            collapseLongMessages: false,
            showPackOwner: false
        )
    }

    public init(
        hideStories: Bool = false,
        hideAiFeatures: Bool = false,
        secondsInMessages: Bool = false,
        confirmCalls: Bool = false,
        doubleTapToEdit: Bool = false,
        showProfileId: Bool = false,
        showDC: Bool = false,
        hidePhoneInSettings: Bool = false,
        hideContextMenuReply: Bool = false,
        hideContextMenuPin: Bool = false,
        hideContextMenuForward: Bool = false,
        hideContextMenuReport: Bool = false,
        hideContextMenuSelect: Bool = false,
        doubleTapDelay: Int32 = 300,
        animationSpeed: Double = 1.0,
        defaultEmojisFirst: Bool = false,
        disableScrollToNextChannel: Bool = false,
        showInlineReactions: Bool = false,
        blockCloudDrafts: Bool = false,
        showForwardedTime: Bool = false,
        noSelectionCap: Bool = false,
        stripTrackingParams: Bool = false,
        replacePreviewLinks: Bool = false,
        confirmInternalLinks: Bool = false,
        biometricConfirmation: Bool = false,
        hideSponsoredMessages: Bool = false,
        hideStarReactionButton: Bool = false,
        hideStarReactionCount: Bool = false,
        hideSimilarChannels: Bool = false,
        warnPollsRevote: Bool = false,
        showPackOwner: Bool = false,
        timeOnServiceMessages: Bool = false,
        showTabNames: Bool = false,
        compactChatList: Bool = false,
        chatListLines: Int32 = 2,
        compactFolderNames: Bool = false,
        allChatsHidden: Bool = false,
        hideTabBar: Bool = false,
        wideTabBar: Bool = false,
        tabBarSearchEnabled: Bool = false,
        wideChannelPosts: Bool = false,
        hideChannelBottomButton: Bool = false,
        disableGalleryCamera: Bool = false,
        disableGalleryCameraPreview: Bool = false,
        disableStoryCameraSwipe: Bool = false,
        enableMultiColumnLayout: Bool = false,
        flatStickerCorners: Bool = false,
        saveStickerToPhotos: Bool = false,
        collapseLongMessages: Bool = false,
        showPackOwner: Bool = false
    ) {
        self.hideStories = hideStories
        self.hideAiFeatures = hideAiFeatures
        self.secondsInMessages = secondsInMessages
        self.confirmCalls = confirmCalls
        self.doubleTapToEdit = doubleTapToEdit
        self.showProfileId = showProfileId
        self.showDC = showDC
        self.hidePhoneInSettings = hidePhoneInSettings
        self.hideContextMenuReply = hideContextMenuReply
        self.hideContextMenuPin = hideContextMenuPin
        self.hideContextMenuForward = hideContextMenuForward
        self.hideContextMenuReport = hideContextMenuReport
        self.hideContextMenuSelect = hideContextMenuSelect
        self.doubleTapDelay = doubleTapDelay
        self.animationSpeed = animationSpeed
        self.defaultEmojisFirst = defaultEmojisFirst
        self.disableScrollToNextChannel = disableScrollToNextChannel
        self.showInlineReactions = showInlineReactions
        self.blockCloudDrafts = blockCloudDrafts
        self.showForwardedTime = showForwardedTime
        self.noSelectionCap = noSelectionCap
        self.stripTrackingParams = stripTrackingParams
        self.replacePreviewLinks = replacePreviewLinks
        self.confirmInternalLinks = confirmInternalLinks
        self.biometricConfirmation = biometricConfirmation
        self.hideSponsoredMessages = hideSponsoredMessages
        self.hideStarReactionButton = hideStarReactionButton
        self.hideStarReactionCount = hideStarReactionCount
        self.hideSimilarChannels = hideSimilarChannels
        self.warnPollsRevote = warnPollsRevote
        self.showPackOwner = showPackOwner
        self.timeOnServiceMessages = timeOnServiceMessages
        self.showTabNames = showTabNames
        self.compactChatList = compactChatList
        self.chatListLines = chatListLines
        self.compactFolderNames = compactFolderNames
        self.allChatsHidden = allChatsHidden
        self.hideTabBar = hideTabBar
        self.wideTabBar = wideTabBar
        self.tabBarSearchEnabled = tabBarSearchEnabled
        self.wideChannelPosts = wideChannelPosts
        self.hideChannelBottomButton = hideChannelBottomButton
        self.disableGalleryCamera = disableGalleryCamera
        self.disableGalleryCameraPreview = disableGalleryCameraPreview
        self.disableStoryCameraSwipe = disableStoryCameraSwipe
        self.enableMultiColumnLayout = enableMultiColumnLayout
        self.flatStickerCorners = flatStickerCorners
        self.saveStickerToPhotos = saveStickerToPhotos
        self.collapseLongMessages = collapseLongMessages
        self.showPackOwner = showPackOwner
    }

    // Backward-compatible Decodable: uses decodeIfPresent so old persisted data missing
    // newly-added keys decodes to defaults instead of failing (which would wipe all settings).
    private enum CodingKeys: String, CodingKey {
        case hideStories, hideAiFeatures, secondsInMessages, confirmCalls, doubleTapToEdit
        case showProfileId, showDC, hidePhoneInSettings
        case hideContextMenuReply, hideContextMenuPin, hideContextMenuForward, hideContextMenuReport, hideContextMenuSelect
        case doubleTapDelay, animationSpeed, defaultEmojisFirst, disableScrollToNextChannel, showInlineReactions
        case blockCloudDrafts, showForwardedTime, noSelectionCap, stripTrackingParams, replacePreviewLinks, confirmInternalLinks, biometricConfirmation
        case hideSponsoredMessages, hideStarReactionButton, hideStarReactionCount, hideSimilarChannels, warnPollsRevote, showPackOwner, timeOnServiceMessages
        case showTabNames, compactChatList, chatListLines, compactFolderNames, allChatsHidden, hideTabBar, wideTabBar, tabBarSearchEnabled, wideChannelPosts, hideChannelBottomButton
        case disableGalleryCamera, disableGalleryCameraPreview, disableStoryCameraSwipe, enableMultiColumnLayout
        case flatStickerCorners
        case saveStickerToPhotos
        case collapseLongMessages
        case showPackOwner
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hideStories = try c.decodeIfPresent(Bool.self, forKey: .hideStories) ?? false
        self.hideAiFeatures = try c.decodeIfPresent(Bool.self, forKey: .hideAiFeatures) ?? false
        self.secondsInMessages = try c.decodeIfPresent(Bool.self, forKey: .secondsInMessages) ?? false
        self.confirmCalls = try c.decodeIfPresent(Bool.self, forKey: .confirmCalls) ?? false
        self.doubleTapToEdit = try c.decodeIfPresent(Bool.self, forKey: .doubleTapToEdit) ?? false
        self.showProfileId = try c.decodeIfPresent(Bool.self, forKey: .showProfileId) ?? false
        self.showDC = try c.decodeIfPresent(Bool.self, forKey: .showDC) ?? false
        self.hidePhoneInSettings = try c.decodeIfPresent(Bool.self, forKey: .hidePhoneInSettings) ?? false
        self.hideContextMenuReply = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuReply) ?? false
        self.hideContextMenuPin = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuPin) ?? false
        self.hideContextMenuForward = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuForward) ?? false
        self.hideContextMenuReport = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuReport) ?? false
        self.hideContextMenuSelect = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuSelect) ?? false
        self.doubleTapDelay = try c.decodeIfPresent(Int32.self, forKey: .doubleTapDelay) ?? 300
        self.animationSpeed = try c.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? 1.0
        self.defaultEmojisFirst = try c.decodeIfPresent(Bool.self, forKey: .defaultEmojisFirst) ?? false
        self.disableScrollToNextChannel = try c.decodeIfPresent(Bool.self, forKey: .disableScrollToNextChannel) ?? false
        self.showInlineReactions = try c.decodeIfPresent(Bool.self, forKey: .showInlineReactions) ?? false
        self.blockCloudDrafts = try c.decodeIfPresent(Bool.self, forKey: .blockCloudDrafts) ?? false
        self.showForwardedTime = try c.decodeIfPresent(Bool.self, forKey: .showForwardedTime) ?? false
        self.noSelectionCap = try c.decodeIfPresent(Bool.self, forKey: .noSelectionCap) ?? false
        self.stripTrackingParams = try c.decodeIfPresent(Bool.self, forKey: .stripTrackingParams) ?? false
        self.replacePreviewLinks = try c.decodeIfPresent(Bool.self, forKey: .replacePreviewLinks) ?? false
        self.confirmInternalLinks = try c.decodeIfPresent(Bool.self, forKey: .confirmInternalLinks) ?? false
        self.biometricConfirmation = try c.decodeIfPresent(Bool.self, forKey: .biometricConfirmation) ?? false
        self.hideSponsoredMessages = try c.decodeIfPresent(Bool.self, forKey: .hideSponsoredMessages) ?? false
        self.hideStarReactionButton = try c.decodeIfPresent(Bool.self, forKey: .hideStarReactionButton) ?? false
        self.hideStarReactionCount = try c.decodeIfPresent(Bool.self, forKey: .hideStarReactionCount) ?? false
        self.hideSimilarChannels = try c.decodeIfPresent(Bool.self, forKey: .hideSimilarChannels) ?? false
        self.warnPollsRevote = try c.decodeIfPresent(Bool.self, forKey: .warnPollsRevote) ?? false
        self.showPackOwner = try c.decodeIfPresent(Bool.self, forKey: .showPackOwner) ?? false
        self.timeOnServiceMessages = try c.decodeIfPresent(Bool.self, forKey: .timeOnServiceMessages) ?? false
        self.showTabNames = try c.decodeIfPresent(Bool.self, forKey: .showTabNames) ?? false
        self.compactChatList = try c.decodeIfPresent(Bool.self, forKey: .compactChatList) ?? false
        self.chatListLines = try c.decodeIfPresent(Int32.self, forKey: .chatListLines) ?? 2
        self.compactFolderNames = try c.decodeIfPresent(Bool.self, forKey: .compactFolderNames) ?? false
        self.allChatsHidden = try c.decodeIfPresent(Bool.self, forKey: .allChatsHidden) ?? false
        self.hideTabBar = try c.decodeIfPresent(Bool.self, forKey: .hideTabBar) ?? false
        self.wideTabBar = try c.decodeIfPresent(Bool.self, forKey: .wideTabBar) ?? false
        self.tabBarSearchEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabBarSearchEnabled) ?? false
        self.wideChannelPosts = try c.decodeIfPresent(Bool.self, forKey: .wideChannelPosts) ?? false
        self.hideChannelBottomButton = try c.decodeIfPresent(Bool.self, forKey: .hideChannelBottomButton) ?? false
        self.disableGalleryCamera = try c.decodeIfPresent(Bool.self, forKey: .disableGalleryCamera) ?? false
        self.disableGalleryCameraPreview = try c.decodeIfPresent(Bool.self, forKey: .disableGalleryCameraPreview) ?? false
        self.disableStoryCameraSwipe = try c.decodeIfPresent(Bool.self, forKey: .disableStoryCameraSwipe) ?? false
        self.enableMultiColumnLayout = try c.decodeIfPresent(Bool.self, forKey: .enableMultiColumnLayout) ?? false
        self.flatStickerCorners = try c.decodeIfPresent(Bool.self, forKey: .flatStickerCorners) ?? false
        self.saveStickerToPhotos = try c.decodeIfPresent(Bool.self, forKey: .saveStickerToPhotos) ?? false
        self.collapseLongMessages = try c.decodeIfPresent(Bool.self, forKey: .collapseLongMessages) ?? false
        self.showPackOwner = try c.decodeIfPresent(Bool.self, forKey: .showPackOwner) ?? false
    }
}

public func updateClearConfigInteractively(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ f: @escaping (ClearConfigSettings) -> ClearConfigSettings
) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.clearConfigSettings) { entry in
            let current = entry?.get(ClearConfigSettings.self) ?? ClearConfigSettings.defaultSettings
            return SharedPreferencesEntry(f(current))
        }
    }
}

public func clearConfigEntry(
    accountManager: AccountManager<TelegramAccountManagerTypes>
) -> Signal<ClearConfigSettings, NoError> {
    return accountManager.sharedData(
        keys: [ApplicationSpecificSharedDataKeys.clearConfigSettings]
    )
    |> map { sharedData -> ClearConfigSettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.clearConfigSettings]?.get(ClearConfigSettings.self) ?? ClearConfigSettings.defaultSettings
    }
}
