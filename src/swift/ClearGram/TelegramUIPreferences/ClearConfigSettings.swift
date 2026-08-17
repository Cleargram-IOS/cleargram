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
    public var showRegistrationDate: Bool
    public var showPhoneCountry: Bool
    public var hidePhoneInSettings: Bool
    public var hideContextMenuReply: Bool
    public var hideContextMenuPin: Bool
    public var hideContextMenuForward: Bool
    public var hideContextMenuReport: Bool
    public var hideContextMenuSelect: Bool
    public var doubleTapDelay: Int32
    public var defaultEmojisFirst: Bool
    public var disableScrollToNextChannel: Bool
    public var showInlineReactions: Bool
    public var blockCloudDrafts: Bool
    public var showForwardedTime: Bool
    public var stripTrackingParams: Bool
    public var replacePreviewLinks: Bool
    public var confirmInternalLinks: Bool
    public var biometricConfirmDeleteChat: Bool
    public var biometricConfirmClearHistory: Bool
    public var biometricConfirmLogout: Bool
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
    public var narrowTabBar: Bool
    public var tabBarSearchEnabled: Bool
    public var wideChannelPosts: Bool
    public var hideChannelBottomButton: Bool
    public var disableGalleryCamera: Bool
    public var compactGalleryCamera: Bool
    public var disableStoryCameraSwipe: Bool
    public var enableMultiColumnLayout: Bool
    public var flatStickerCorners: Bool
    public var saveStickerToPhotos: Bool
    public var collapseLongMessages: Bool
    public var disableContactsTab: Bool
    public var disableCallsButton: Bool
    public var showAudioFormatBitrate: Bool
    public var allChatsTitleLengthOverride: Int32
    public var fontSizeOverride: Bool
    public var searchByUserId: Bool
    public var adminLogsImprovements: Bool
    public var paranoiaMode: Bool
    public var hideChannelJoinRequests: Bool
    public var fasterFileLoad: Bool
    public var videoCircleAudioSource: Bool
    public var videoQualityOriginalToggle: Bool
    public var sendVideoAsCircle: Bool
    public var hidePremiumStarsGifts: Bool
    public var copyImageInGallery: Bool
    public var videoMessageCameraSelection: Bool
    public var copyBotButtonUrl: Bool
    public var hideChatListPromoNotices: Bool
    public var hideChatListBirthdayNotices: Bool
    public var recentStickersLimit: Int32
    public var swipeActionPin: Bool
    public var swipeActionMute: Bool
    public var swipeActionRead: Bool
    public var swipeActionDelete: Bool
    public var swipeActionArchive: Bool
    public var swipeActionsLeft: [String]
    public var swipeActionsRight: [String]
    public var importSettingsFromChats: Bool
    public var lastFmScrobbling: Bool
    public var lastFmNowPlaying: Bool
    // Candidate speech-recognition locales for on-device transcription ("ru-RU", "en-US"…),
    // in priority order. Empty = the system language, which is what stock uses and the only
    // thing it can use. Each entry costs another pass over the audio — see
    // ClearConfig.maxTranscriptionLocales.
    public var transcriptionLocales: [String]

    public static var defaultSettings: ClearConfigSettings {
        return ClearConfigSettings(
            hideStories: false,
            hideAiFeatures: false,
            secondsInMessages: false,
            confirmCalls: false,
            doubleTapToEdit: false,
            showProfileId: false,
            showDC: false,
            showRegistrationDate: false,
            showPhoneCountry: false,
            hidePhoneInSettings: false,
            hideContextMenuReply: false,
            hideContextMenuPin: false,
            hideContextMenuForward: false,
            hideContextMenuReport: false,
            hideContextMenuSelect: false,
            doubleTapDelay: 300,
            defaultEmojisFirst: false,
            disableScrollToNextChannel: false,
            showInlineReactions: false,
            blockCloudDrafts: false,
            showForwardedTime: false,
            stripTrackingParams: false,
            replacePreviewLinks: false,
            confirmInternalLinks: false,
            biometricConfirmDeleteChat: false,
            biometricConfirmClearHistory: false,
            biometricConfirmLogout: false,
            hideStarReactionButton: false,
            hideStarReactionCount: false,
            hideSimilarChannels: false,
            warnPollsRevote: false,
            showPackOwner: false,
            timeOnServiceMessages: false,
            showTabNames: true,
            compactChatList: false,
            chatListLines: 3,
            compactFolderNames: false,
            allChatsHidden: false,
            hideTabBar: false,
            narrowTabBar: false,
            tabBarSearchEnabled: true,
            wideChannelPosts: false,
            hideChannelBottomButton: false,
            disableGalleryCamera: false,
            compactGalleryCamera: false,
            disableStoryCameraSwipe: false,
            enableMultiColumnLayout: false,
            flatStickerCorners: false,
            saveStickerToPhotos: false,
            collapseLongMessages: false,
            disableContactsTab: false,
            disableCallsButton: false,
            showAudioFormatBitrate: false,
            allChatsTitleLengthOverride: 0,
            fontSizeOverride: false,
            searchByUserId: false,
            adminLogsImprovements: false,
            paranoiaMode: false,
            hideChannelJoinRequests: false,
            fasterFileLoad: false,
            videoCircleAudioSource: false,
            videoQualityOriginalToggle: false,
            sendVideoAsCircle: false,
            hidePremiumStarsGifts: false,
            copyImageInGallery: false,
            videoMessageCameraSelection: false,
            copyBotButtonUrl: false,
            hideChatListPromoNotices: false,
            hideChatListBirthdayNotices: false,
            recentStickersLimit: 0,
            swipeActionPin: true,
            swipeActionMute: true,
            swipeActionRead: true,
            swipeActionDelete: true,
            swipeActionArchive: true,
            swipeActionsLeft: [],
            swipeActionsRight: [],
            importSettingsFromChats: true,
            lastFmScrobbling: false,
            lastFmNowPlaying: false,
            transcriptionLocales: []
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
        showRegistrationDate: Bool = false,
        showPhoneCountry: Bool = false,
        hidePhoneInSettings: Bool = false,
        hideContextMenuReply: Bool = false,
        hideContextMenuPin: Bool = false,
        hideContextMenuForward: Bool = false,
        hideContextMenuReport: Bool = false,
        hideContextMenuSelect: Bool = false,
        doubleTapDelay: Int32 = 300,
        defaultEmojisFirst: Bool = false,
        disableScrollToNextChannel: Bool = false,
        showInlineReactions: Bool = false,
        blockCloudDrafts: Bool = false,
        showForwardedTime: Bool = false,
        stripTrackingParams: Bool = false,
        replacePreviewLinks: Bool = false,
        confirmInternalLinks: Bool = false,
        biometricConfirmDeleteChat: Bool = false,
        biometricConfirmClearHistory: Bool = false,
        biometricConfirmLogout: Bool = false,
        hideStarReactionButton: Bool = false,
        hideStarReactionCount: Bool = false,
        hideSimilarChannels: Bool = false,
        warnPollsRevote: Bool = false,
        showPackOwner: Bool = false,
        timeOnServiceMessages: Bool = false,
        showTabNames: Bool = true,
        compactChatList: Bool = false,
        chatListLines: Int32 = 3,
        compactFolderNames: Bool = false,
        allChatsHidden: Bool = false,
        hideTabBar: Bool = false,
        narrowTabBar: Bool = false,
        tabBarSearchEnabled: Bool = true,
        wideChannelPosts: Bool = false,
        hideChannelBottomButton: Bool = false,
        disableGalleryCamera: Bool = false,
        compactGalleryCamera: Bool = false,
        disableStoryCameraSwipe: Bool = false,
        enableMultiColumnLayout: Bool = false,
        flatStickerCorners: Bool = false,
        saveStickerToPhotos: Bool = false,
        collapseLongMessages: Bool = false,
        disableContactsTab: Bool = false,
        disableCallsButton: Bool = false,
        showAudioFormatBitrate: Bool = false,
        allChatsTitleLengthOverride: Int32 = 0,
        fontSizeOverride: Bool = false,
        searchByUserId: Bool = false,
        adminLogsImprovements: Bool = false,
        paranoiaMode: Bool = false,
        hideChannelJoinRequests: Bool = false,
        fasterFileLoad: Bool = false,
        videoCircleAudioSource: Bool = false,
        videoQualityOriginalToggle: Bool = false,
        sendVideoAsCircle: Bool = false,
        hidePremiumStarsGifts: Bool = false,
        copyImageInGallery: Bool = false,
        videoMessageCameraSelection: Bool = false,
        copyBotButtonUrl: Bool = false,
        hideChatListPromoNotices: Bool = false,
        hideChatListBirthdayNotices: Bool = false,
        recentStickersLimit: Int32 = 0,
        swipeActionPin: Bool = true,
        swipeActionMute: Bool = true,
        swipeActionRead: Bool = true,
        swipeActionDelete: Bool = true,
        swipeActionArchive: Bool = true,
        swipeActionsLeft: [String] = [],
        swipeActionsRight: [String] = [],
        importSettingsFromChats: Bool = true,
        lastFmScrobbling: Bool = false,
        lastFmNowPlaying: Bool = false,
        transcriptionLocales: [String] = []
    ) {
        self.hideStories = hideStories
        self.hideAiFeatures = hideAiFeatures
        self.secondsInMessages = secondsInMessages
        self.confirmCalls = confirmCalls
        self.doubleTapToEdit = doubleTapToEdit
        self.showProfileId = showProfileId
        self.showDC = showDC
        self.showRegistrationDate = showRegistrationDate
        self.showPhoneCountry = showPhoneCountry
        self.hidePhoneInSettings = hidePhoneInSettings
        self.hideContextMenuReply = hideContextMenuReply
        self.hideContextMenuPin = hideContextMenuPin
        self.hideContextMenuForward = hideContextMenuForward
        self.hideContextMenuReport = hideContextMenuReport
        self.hideContextMenuSelect = hideContextMenuSelect
        self.doubleTapDelay = doubleTapDelay
        self.defaultEmojisFirst = defaultEmojisFirst
        self.disableScrollToNextChannel = disableScrollToNextChannel
        self.showInlineReactions = showInlineReactions
        self.blockCloudDrafts = blockCloudDrafts
        self.showForwardedTime = showForwardedTime
        self.stripTrackingParams = stripTrackingParams
        self.replacePreviewLinks = replacePreviewLinks
        self.confirmInternalLinks = confirmInternalLinks
        self.biometricConfirmDeleteChat = biometricConfirmDeleteChat
        self.biometricConfirmClearHistory = biometricConfirmClearHistory
        self.biometricConfirmLogout = biometricConfirmLogout
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
        self.narrowTabBar = narrowTabBar
        self.tabBarSearchEnabled = tabBarSearchEnabled
        self.wideChannelPosts = wideChannelPosts
        self.hideChannelBottomButton = hideChannelBottomButton
        self.disableGalleryCamera = disableGalleryCamera
        self.compactGalleryCamera = compactGalleryCamera
        self.disableStoryCameraSwipe = disableStoryCameraSwipe
        self.enableMultiColumnLayout = enableMultiColumnLayout
        self.flatStickerCorners = flatStickerCorners
        self.saveStickerToPhotos = saveStickerToPhotos
        self.collapseLongMessages = collapseLongMessages
        self.disableContactsTab = disableContactsTab
        self.disableCallsButton = disableCallsButton
        self.showAudioFormatBitrate = showAudioFormatBitrate
        self.allChatsTitleLengthOverride = allChatsTitleLengthOverride
        self.fontSizeOverride = fontSizeOverride
        self.searchByUserId = searchByUserId
        self.adminLogsImprovements = adminLogsImprovements
        self.paranoiaMode = paranoiaMode
        self.hideChannelJoinRequests = hideChannelJoinRequests
        self.fasterFileLoad = fasterFileLoad
        self.videoCircleAudioSource = videoCircleAudioSource
        self.videoQualityOriginalToggle = videoQualityOriginalToggle
        self.sendVideoAsCircle = sendVideoAsCircle
        self.hidePremiumStarsGifts = hidePremiumStarsGifts
        self.copyImageInGallery = copyImageInGallery
        self.videoMessageCameraSelection = videoMessageCameraSelection
        self.copyBotButtonUrl = copyBotButtonUrl
        self.hideChatListPromoNotices = hideChatListPromoNotices
        self.hideChatListBirthdayNotices = hideChatListBirthdayNotices
        self.recentStickersLimit = recentStickersLimit
        self.swipeActionPin = swipeActionPin
        self.swipeActionMute = swipeActionMute
        self.swipeActionRead = swipeActionRead
        self.swipeActionDelete = swipeActionDelete
        self.swipeActionArchive = swipeActionArchive
        self.swipeActionsLeft = swipeActionsLeft
        self.swipeActionsRight = swipeActionsRight
        self.importSettingsFromChats = importSettingsFromChats
        self.lastFmScrobbling = lastFmScrobbling
        self.lastFmNowPlaying = lastFmNowPlaying
        self.transcriptionLocales = transcriptionLocales
    }

    // Backward-compatible Decodable: uses decodeIfPresent so old persisted data missing
    // newly-added keys decodes to defaults instead of failing (which would wipe all settings).
    private enum CodingKeys: String, CodingKey {
        case hideStories, hideAiFeatures, secondsInMessages, confirmCalls, doubleTapToEdit
        case showProfileId, showDC, showRegistrationDate, showPhoneCountry, hidePhoneInSettings
        case hideContextMenuReply, hideContextMenuPin, hideContextMenuForward, hideContextMenuReport, hideContextMenuSelect
        case doubleTapDelay, defaultEmojisFirst, disableScrollToNextChannel, showInlineReactions
        case blockCloudDrafts, showForwardedTime, stripTrackingParams, replacePreviewLinks, confirmInternalLinks, biometricConfirmDeleteChat, biometricConfirmClearHistory, biometricConfirmLogout
        case hideStarReactionButton, hideStarReactionCount, hideSimilarChannels, warnPollsRevote, showPackOwner, timeOnServiceMessages
        case showTabNames, compactChatList, chatListLines, compactFolderNames, allChatsHidden, hideTabBar, narrowTabBar, tabBarSearchEnabled, wideChannelPosts, hideChannelBottomButton
        case disableGalleryCamera, compactGalleryCamera, disableStoryCameraSwipe, enableMultiColumnLayout
        case flatStickerCorners
        case saveStickerToPhotos
        case collapseLongMessages
        case disableContactsTab, disableCallsButton, showAudioFormatBitrate, allChatsTitleLengthOverride, fontSizeOverride
        case searchByUserId, adminLogsImprovements, paranoiaMode, hideChannelJoinRequests
        case fasterFileLoad, videoCircleAudioSource, videoQualityOriginalToggle, sendVideoAsCircle, hidePremiumStarsGifts
        case copyImageInGallery, videoMessageCameraSelection, copyBotButtonUrl
        case hideChatListPromoNotices, hideChatListBirthdayNotices
        case recentStickersLimit
        case swipeActionPin, swipeActionMute, swipeActionRead, swipeActionDelete, swipeActionArchive, swipeActionsLeft, swipeActionsRight
        case importSettingsFromChats
        case lastFmScrobbling, lastFmNowPlaying, transcriptionLocales
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
        self.showRegistrationDate = try c.decodeIfPresent(Bool.self, forKey: .showRegistrationDate) ?? false
        self.showPhoneCountry = try c.decodeIfPresent(Bool.self, forKey: .showPhoneCountry) ?? false
        self.hidePhoneInSettings = try c.decodeIfPresent(Bool.self, forKey: .hidePhoneInSettings) ?? false
        self.hideContextMenuReply = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuReply) ?? false
        self.hideContextMenuPin = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuPin) ?? false
        self.hideContextMenuForward = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuForward) ?? false
        self.hideContextMenuReport = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuReport) ?? false
        self.hideContextMenuSelect = try c.decodeIfPresent(Bool.self, forKey: .hideContextMenuSelect) ?? false
        self.doubleTapDelay = try c.decodeIfPresent(Int32.self, forKey: .doubleTapDelay) ?? 300
        self.defaultEmojisFirst = try c.decodeIfPresent(Bool.self, forKey: .defaultEmojisFirst) ?? false
        self.disableScrollToNextChannel = try c.decodeIfPresent(Bool.self, forKey: .disableScrollToNextChannel) ?? false
        self.showInlineReactions = try c.decodeIfPresent(Bool.self, forKey: .showInlineReactions) ?? false
        self.blockCloudDrafts = try c.decodeIfPresent(Bool.self, forKey: .blockCloudDrafts) ?? false
        self.showForwardedTime = try c.decodeIfPresent(Bool.self, forKey: .showForwardedTime) ?? false
        self.stripTrackingParams = try c.decodeIfPresent(Bool.self, forKey: .stripTrackingParams) ?? false
        self.replacePreviewLinks = try c.decodeIfPresent(Bool.self, forKey: .replacePreviewLinks) ?? false
        self.confirmInternalLinks = try c.decodeIfPresent(Bool.self, forKey: .confirmInternalLinks) ?? false
        self.biometricConfirmDeleteChat = try c.decodeIfPresent(Bool.self, forKey: .biometricConfirmDeleteChat) ?? false
        self.biometricConfirmClearHistory = try c.decodeIfPresent(Bool.self, forKey: .biometricConfirmClearHistory) ?? false
        self.biometricConfirmLogout = try c.decodeIfPresent(Bool.self, forKey: .biometricConfirmLogout) ?? false
        self.hideStarReactionButton = try c.decodeIfPresent(Bool.self, forKey: .hideStarReactionButton) ?? false
        self.hideStarReactionCount = try c.decodeIfPresent(Bool.self, forKey: .hideStarReactionCount) ?? false
        self.hideSimilarChannels = try c.decodeIfPresent(Bool.self, forKey: .hideSimilarChannels) ?? false
        self.warnPollsRevote = try c.decodeIfPresent(Bool.self, forKey: .warnPollsRevote) ?? false
        self.showPackOwner = try c.decodeIfPresent(Bool.self, forKey: .showPackOwner) ?? false
        self.timeOnServiceMessages = try c.decodeIfPresent(Bool.self, forKey: .timeOnServiceMessages) ?? false
        self.showTabNames = try c.decodeIfPresent(Bool.self, forKey: .showTabNames) ?? true
        self.compactChatList = try c.decodeIfPresent(Bool.self, forKey: .compactChatList) ?? false
        self.chatListLines = try c.decodeIfPresent(Int32.self, forKey: .chatListLines) ?? 3
        self.compactFolderNames = try c.decodeIfPresent(Bool.self, forKey: .compactFolderNames) ?? false
        self.allChatsHidden = try c.decodeIfPresent(Bool.self, forKey: .allChatsHidden) ?? false
        self.hideTabBar = try c.decodeIfPresent(Bool.self, forKey: .hideTabBar) ?? false
        self.narrowTabBar = try c.decodeIfPresent(Bool.self, forKey: .narrowTabBar) ?? false
        self.tabBarSearchEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabBarSearchEnabled) ?? true
        self.wideChannelPosts = try c.decodeIfPresent(Bool.self, forKey: .wideChannelPosts) ?? false
        self.hideChannelBottomButton = try c.decodeIfPresent(Bool.self, forKey: .hideChannelBottomButton) ?? false
        self.disableGalleryCamera = try c.decodeIfPresent(Bool.self, forKey: .disableGalleryCamera) ?? false
        self.compactGalleryCamera = try c.decodeIfPresent(Bool.self, forKey: .compactGalleryCamera) ?? false
        self.disableStoryCameraSwipe = try c.decodeIfPresent(Bool.self, forKey: .disableStoryCameraSwipe) ?? false
        self.enableMultiColumnLayout = try c.decodeIfPresent(Bool.self, forKey: .enableMultiColumnLayout) ?? false
        self.flatStickerCorners = try c.decodeIfPresent(Bool.self, forKey: .flatStickerCorners) ?? false
        self.saveStickerToPhotos = try c.decodeIfPresent(Bool.self, forKey: .saveStickerToPhotos) ?? false
        self.collapseLongMessages = try c.decodeIfPresent(Bool.self, forKey: .collapseLongMessages) ?? false
        self.disableContactsTab = try c.decodeIfPresent(Bool.self, forKey: .disableContactsTab) ?? false
        self.disableCallsButton = try c.decodeIfPresent(Bool.self, forKey: .disableCallsButton) ?? false
        self.showAudioFormatBitrate = try c.decodeIfPresent(Bool.self, forKey: .showAudioFormatBitrate) ?? false
        self.allChatsTitleLengthOverride = try c.decodeIfPresent(Int32.self, forKey: .allChatsTitleLengthOverride) ?? 0
        self.fontSizeOverride = try c.decodeIfPresent(Bool.self, forKey: .fontSizeOverride) ?? false
        self.searchByUserId = try c.decodeIfPresent(Bool.self, forKey: .searchByUserId) ?? false
        self.adminLogsImprovements = try c.decodeIfPresent(Bool.self, forKey: .adminLogsImprovements) ?? false
        self.paranoiaMode = try c.decodeIfPresent(Bool.self, forKey: .paranoiaMode) ?? false
        self.hideChannelJoinRequests = try c.decodeIfPresent(Bool.self, forKey: .hideChannelJoinRequests) ?? false
        self.fasterFileLoad = try c.decodeIfPresent(Bool.self, forKey: .fasterFileLoad) ?? false
        self.videoCircleAudioSource = try c.decodeIfPresent(Bool.self, forKey: .videoCircleAudioSource) ?? false
        self.videoQualityOriginalToggle = try c.decodeIfPresent(Bool.self, forKey: .videoQualityOriginalToggle) ?? false
        self.sendVideoAsCircle = try c.decodeIfPresent(Bool.self, forKey: .sendVideoAsCircle) ?? false
        self.hidePremiumStarsGifts = try c.decodeIfPresent(Bool.self, forKey: .hidePremiumStarsGifts) ?? false
        self.copyImageInGallery = try c.decodeIfPresent(Bool.self, forKey: .copyImageInGallery) ?? false
        self.videoMessageCameraSelection = try c.decodeIfPresent(Bool.self, forKey: .videoMessageCameraSelection) ?? false
        self.copyBotButtonUrl = try c.decodeIfPresent(Bool.self, forKey: .copyBotButtonUrl) ?? false
        self.hideChatListPromoNotices = try c.decodeIfPresent(Bool.self, forKey: .hideChatListPromoNotices) ?? false
        self.hideChatListBirthdayNotices = try c.decodeIfPresent(Bool.self, forKey: .hideChatListBirthdayNotices) ?? false
        self.recentStickersLimit = try c.decodeIfPresent(Int32.self, forKey: .recentStickersLimit) ?? 0
        self.swipeActionPin = try c.decodeIfPresent(Bool.self, forKey: .swipeActionPin) ?? true
        self.swipeActionMute = try c.decodeIfPresent(Bool.self, forKey: .swipeActionMute) ?? true
        self.swipeActionRead = try c.decodeIfPresent(Bool.self, forKey: .swipeActionRead) ?? true
        self.swipeActionDelete = try c.decodeIfPresent(Bool.self, forKey: .swipeActionDelete) ?? true
        self.swipeActionArchive = try c.decodeIfPresent(Bool.self, forKey: .swipeActionArchive) ?? true
        self.swipeActionsLeft = try c.decodeIfPresent([String].self, forKey: .swipeActionsLeft) ?? []
        self.swipeActionsRight = try c.decodeIfPresent([String].self, forKey: .swipeActionsRight) ?? []
        // Deliberately the one default-ON toggle: the intercept only ever fires on the
        // `.cleargram` extension, which does not exist in stock, so no real file type changes
        // behaviour. Import still always asks before applying anything.
        self.importSettingsFromChats = try c.decodeIfPresent(Bool.self, forKey: .importSettingsFromChats) ?? true
        self.lastFmScrobbling = try c.decodeIfPresent(Bool.self, forKey: .lastFmScrobbling) ?? false
        self.lastFmNowPlaying = try c.decodeIfPresent(Bool.self, forKey: .lastFmNowPlaying) ?? false
        self.transcriptionLocales = try c.decodeIfPresent([String].self, forKey: .transcriptionLocales) ?? []
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
