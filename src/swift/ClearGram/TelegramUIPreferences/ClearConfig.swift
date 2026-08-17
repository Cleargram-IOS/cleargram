import Foundation
import SwiftSignalKit
import TelegramCore

// Facade over ClearConfigSettings. Call sites use `ClearConfig.hideStories.value` etc.
// The current snapshot is cached in memory and refreshed from shared-data via
// `ClearConfig.start(accountManager:)`. Default-off — every toggle reads as stock when
// uninitialized.

public enum ClearConfig {
    private static let cache = Atomic<ClearConfigSettings>(value: ClearConfigSettings.defaultSettings)

    public static func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        // fork strings follow the client language, mirrored from shared-data the same way
        ClearStrings.start(accountManager: accountManager)

        // Last.fm credentials live in their own shared-data key (33), not in ClearConfigSettings —
        // same mirroring, so the scrobbler can read them from any queue.
        ClearLastFm.start(accountManager: accountManager)

        // keep the in-memory cache in sync with shared-data
        _ = clearConfigEntry(accountManager: accountManager).start(next: { value in
            _ = cache.swap(value)
            _ = ClearHooks.blockCloudDrafts.swap(value.blockCloudDrafts)
            _ = ClearHooks.fasterFileLoad.swap(value.fasterFileLoad)
            _ = ClearHooks.hideStories.swap(value.hideStories)
            _ = ClearHooks.recentStickersLimit.swap(value.recentStickersLimit)
        })
    }

    public static func current() -> ClearConfigSettings {
        return cache.with { $0 }
    }

    public static func update(
        accountManager: AccountManager<TelegramAccountManagerTypes>,
        _ f: @escaping (ClearConfigSettings) -> ClearConfigSettings
    ) -> Signal<Void, NoError> {
        return updateClearConfigInteractively(accountManager: accountManager, f)
    }

    public static func reset(
        accountManager: AccountManager<TelegramAccountManagerTypes>
    ) -> Signal<Void, NoError> {
        return updateClearConfigInteractively(accountManager: accountManager, { _ in ClearConfigSettings.defaultSettings })
    }

    // individual toggles — add as ClearConfigSettings grows
    public static var hideStories: Bool { current().hideStories }
    public static var hideAiFeatures: Bool { current().hideAiFeatures }
    public static var secondsInMessages: Bool { current().secondsInMessages }
    public static var confirmCalls: Bool { current().confirmCalls }
    public static var doubleTapToEdit: Bool { current().doubleTapToEdit }
    public static var showProfileId: Bool { current().showProfileId }
    public static var showDC: Bool { current().showDC }
    public static var showRegistrationDate: Bool { current().showRegistrationDate }
    public static var showPhoneCountry: Bool { current().showPhoneCountry }
    public static var hidePhoneInSettings: Bool { current().hidePhoneInSettings }
    public static var hideContextMenuReply: Bool { current().hideContextMenuReply }
    public static var hideContextMenuPin: Bool { current().hideContextMenuPin }
    public static var hideContextMenuForward: Bool { current().hideContextMenuForward }
    public static var hideContextMenuReport: Bool { current().hideContextMenuReport }
    public static var hideContextMenuSelect: Bool { current().hideContextMenuSelect }
    public static var doubleTapDelay: Int32 { current().doubleTapDelay }
    public static var defaultEmojisFirst: Bool { current().defaultEmojisFirst }
    public static var disableScrollToNextChannel: Bool { current().disableScrollToNextChannel }
    public static var showInlineReactions: Bool { current().showInlineReactions }
    public static var blockCloudDrafts: Bool { current().blockCloudDrafts }
    public static var showForwardedTime: Bool { current().showForwardedTime }
    public static var stripTrackingParams: Bool { current().stripTrackingParams }
    public static var replacePreviewLinks: Bool { current().replacePreviewLinks }
    public static var confirmInternalLinks: Bool { current().confirmInternalLinks }
    public static var biometricConfirmDeleteChat: Bool { current().biometricConfirmDeleteChat }
    public static var biometricConfirmClearHistory: Bool { current().biometricConfirmClearHistory }
    public static var biometricConfirmLogout: Bool { current().biometricConfirmLogout }
    public static var hideStarReactionButton: Bool { current().hideStarReactionButton }
    public static var hideStarReactionCount: Bool { current().hideStarReactionCount }
    public static var hideSimilarChannels: Bool { current().hideSimilarChannels }
    public static var warnPollsRevote: Bool { current().warnPollsRevote }
    public static var showPackOwner: Bool { current().showPackOwner }
    public static var timeOnServiceMessages: Bool { current().timeOnServiceMessages }
    public static var showTabNames: Bool { current().showTabNames }
    public static var compactChatList: Bool { current().compactChatList }
    public static var chatListLines: Int32 { current().chatListLines }
    public static var compactMessagePreview: Bool { current().chatListLines != 3 }
    public static var compactFolderNames: Bool { current().compactFolderNames }
    public static var allChatsHidden: Bool { current().allChatsHidden }
    public static var hideTabBar: Bool { current().hideTabBar }
    public static var narrowTabBar: Bool { current().narrowTabBar }
    public static var tabBarSearchEnabled: Bool { current().tabBarSearchEnabled }
    public static var wideChannelPosts: Bool { current().wideChannelPosts }
    public static var hideChannelBottomButton: Bool { current().hideChannelBottomButton }
    public static var disableGalleryCamera: Bool { current().disableGalleryCamera }
    public static var compactGalleryCamera: Bool { current().compactGalleryCamera }
    public static var disableStoryCameraSwipe: Bool { current().disableStoryCameraSwipe }
    public static var enableMultiColumnLayout: Bool { current().enableMultiColumnLayout }
    public static var flatStickerCorners: Bool { current().flatStickerCorners }
    public static var saveStickerToPhotos: Bool { current().saveStickerToPhotos }
    public static var collapseLongMessages: Bool { current().collapseLongMessages }
    public static var disableContactsTab: Bool { current().disableContactsTab }
    public static var disableCallsButton: Bool { current().disableCallsButton }
    public static var showAudioFormatBitrate: Bool { current().showAudioFormatBitrate }
    public static var allChatsTitleLengthOverride: Int32 { current().allChatsTitleLengthOverride }
    public static var fontSizeOverride: Bool { current().fontSizeOverride }
    public static var searchByUserId: Bool { current().searchByUserId }
    public static var adminLogsImprovements: Bool { current().adminLogsImprovements }
    public static var paranoiaMode: Bool { current().paranoiaMode }
    public static var hideChannelJoinRequests: Bool { current().hideChannelJoinRequests }
    public static var fasterFileLoad: Bool { current().fasterFileLoad }
    public static var videoCircleAudioSource: Bool { current().videoCircleAudioSource }
    public static var videoQualityOriginalToggle: Bool { current().videoQualityOriginalToggle }
    public static var sendVideoAsCircle: Bool { current().sendVideoAsCircle }
    public static var hidePremiumStarsGifts: Bool { current().hidePremiumStarsGifts }
    public static var copyImageInGallery: Bool { current().copyImageInGallery }
    public static var videoMessageCameraSelection: Bool { current().videoMessageCameraSelection }
    public static var copyBotButtonUrl: Bool { current().copyBotButtonUrl }
    public static var hideChatListPromoNotices: Bool { current().hideChatListPromoNotices }
    public static var hideChatListBirthdayNotices: Bool { current().hideChatListBirthdayNotices }
    public static var recentStickersLimit: Int32 { current().recentStickersLimit }
    public static var swipeActionPin: Bool { current().swipeActionPin }
    public static var swipeActionMute: Bool { current().swipeActionMute }
    public static var swipeActionRead: Bool { current().swipeActionRead }
    public static var swipeActionDelete: Bool { current().swipeActionDelete }
    public static var swipeActionArchive: Bool { current().swipeActionArchive }
    public static var swipeActionsLeft: [String] { current().swipeActionsLeft }
    public static var swipeActionsRight: [String] { current().swipeActionsRight }
    public static var importSettingsFromChats: Bool { current().importSettingsFromChats }
    public static var lastFmScrobbling: Bool { current().lastFmScrobbling }
    public static var lastFmNowPlaying: Bool { current().lastFmNowPlaying }
    public static var transcriptionLocales: [String] { current().transcriptionLocales }
    // Every candidate language is another full recognition pass over the audio, paid on every
    // voice message — so the picker caps the list and the transcriber trims to it. Lives here
    // rather than next to the transcriber so the settings screen can read it without depending
    // on the media modules.
    public static let maxTranscriptionLocales = 3
}

