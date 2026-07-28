# Cleargram — feature & patch list

> Keep in sync: when adding/removing/materially changing a patch, update this file in the
> same changeset.

## Legend

- ✅ implemented
- 🔵 planned
- ⚪ upstream already does it — don't reimplement

## Bugfix

| patch | description |
| --- | --- |
| ✅ `bugfix__recent-inline-bots-duplicate-crash` | fix `EXC_BREAKPOINT` crash in `OrderedItemListTable.replaceItems` (debug-only assertion on duplicate IDs) triggered when the server returns the same inline bot in multiple `topPeers` categories. Dedupe `peersWithRating` by `peerId` (keeping the highest rating) before `replaceOrderedItemListItems` in `_internal_managedRecentlyUsedInlineBots` (`submodules/TelegramCore/Sources/TelegramEngine/Peers/RecentPeers.swift`). Stock bug — not caused by cleargram patches; fires after login when the chat list loads. |

## Features

| patch | description |
| --- | --- |
| ✅ `feature__hidden-chats` | hide selected chats from lists, search, recents; suppress notifications; subtract from app badge. Ported from keetgram `76131c1ec7` + presets `c4650d972a` (net diff against `6ad963e5b6`, since keetgram merged origin/master forward). Fork code: `src/swift/ClearGram/TelegramUIPreferences/HiddenChatsSettings.swift` + `src/swift/ClearGram/DebugSettingsUI/QuietChatsController.swift`. |
| ✅ `feature__hidden-messages` | per-message hide via context-menu (gated by an `enabled` toggle); filtered from chat history, in-chat and global search, and shared-media/gif panes without deleting from the server. Ported from keetgram `f2e0edb417` (net diff against `6ad963e5b6` for 8 stock files; the overlapping `ChatListSearchListPaneNode.swift` was already captured by the hidden-chats net diff). Fork code: `src/swift/ClearGram/TelegramUIPreferences/HiddenMessagesSettings.swift` + `src/swift/ClearGram/DebugSettingsUI/QuietChatsController.swift` (management UI). |
| ✅ `feature__camera-picker-video-messages` | front/back camera picker for video messages. Ported from keetgram `4798e9fd8e` (net diff against `6ad963e5b6`, 7 stock files). Build-verified. |
| ✅ `feature__biometric-confirmation` | Face/Touch ID prompt before destructive actions: delete chat (chat list swipe/menu + in-chat delete), clear history, logout. Three independent toggles (`biometricConfirmDeleteChat`, `biometricConfirmClearHistory`, `biometricConfirmLogout`), default-off. Falls through silently when no biometric is available (simulator / unsupported device) so users are never locked out. Uses the stock `LocalAuth` submodule (`LocalAuth.auth(reason:)`); fork helper `ClearBiometricHelper.gate(reason:enabled:onSuccess:)` in `src/swift/ClearGram/TelegramUIPreferences/`. Stock wiring: gate wrappers via the `Impl`-split pattern (no call-site re-indent) in `ChatListController.schedulePeerChatRemoval`, `ChatController.deleteChat` + `beginClearHistory`, `LogoutOptionsController` logout action; `LocalAuth` BUILD dep added to `TelegramUIPreferences`. Inspired by inugram `7b92f5b`. |
| ✅ `feature__show-audio-format-bitrate` | display audio codec (MP3/AAC/OGG/FLAC/WAV/OPUS) and bitrate (kbps) in the music player subtitle. Extends `SharedMediaPlaybackDisplayData.music` with an optional `formatInfo: String?` parameter (signature change in `AccountContext` — touches 6 stock files: enum + == + 4 call sites + 2 consumer destructure sites). Fork helper `clearAudioFormatInfo(mimeType:size:duration:)` in `src/swift/ClearGram/TelegramUIPreferences/ClearAudioFormatInfo.swift`. Appended to the performer/artist subtitle in `OverlayAudioPlayerControlsNode` (gated by `ClearConfig.showAudioFormatBitrate`, default-off). |
| ✅ `feature__faster-file-load` | bump download/upload chunk sizes for faster file transfer. Download: large files use 1MB part size (up from 512KB) in `MultipartFetch`, non-story uses 512KB (up from 128KB) in `FetchV2`. Upload: `useLargerParts` path uses 512KB (up from 256KB), default uses 256KB (up from 128KB) in `MultipartUpload`. Gated by `ClearConfig.fasterFileLoad` (default-off) bridged into `TelegramCore` via `ClearHooks.fasterFileLoad` (`Atomic<Bool>`), synced from `ClearConfig.start()`. 4 stock files. Inspired by inugram `abe0373`. |
| ✅ `feature__profile-copy-name` | long-press the peer's display name in the profile header to copy it to clipboard. Adds a `UILongPressGestureRecognizer` to `titleNodeRawContainer` in `PeerInfoHeaderNode` (mirroring the existing username/phone long-press pattern), a `displayCopyNameContextMenu` callback, and wiring in `PeerInfoScreen` that shows a context menu with a "Copy" action + undo overlay. Always-on (purely additive — long-press on the name was a no-op in stock). 2 stock files. Inspired by inugram `13aaefb`. |

## Debloat

| patch | description |
| --- | --- |
| ✅ `debloat__hide-ai-features` | hide all AI features behind `ClearConfig.hideAiFeatures` toggle (default-off). Gates: summarize button on messages (`ChatMessageBubbleItemNode`), AI compose button in legacy and new Text Field v2 input panels (`ChatTextInputPanelNode`, `MessageInputPanelComponent` via `isAIEnabled` flag, `AttachmentTextInputPanelNode`, `LegacyMessageInputPanel`), AI button in `RichTextAttachmentScreen`. 12 stock files. UI toggle in Settings → Debug → Cleargram Settings. `ClearConfig.start()` called from `AppDelegate` at launch. |
| ✅ `debloat__hide-channel-join-requests` | hide the "X wants to join" pending-join-request banner in channel/group chats from admins. Gates the `ChatTitlePanelContext.inviteRequests` panel at 3 sites in `ChatControllerLoadDisplayNode.swift` (previous-state flag, current-state `displayActionsPanel` flag, and `.inviteRequests` context-add to `updatedTitlePanelContext`). One stock file, +3/-3 chars. Default-off via `ClearConfig.hideChannelJoinRequests`. |
| ✅ `debloat__hide-channel-bottom-button` | hide the bottom action bar (mute/join/leave buttons) in channel preview chats for non-members. Early-return in `inputPanelForChatPresentationIntefaceState` (`ChatInterfaceStateInputPanels.swift`) when `ClearConfig.hideChannelBottomButton` is on and the peer is a channel with `participationStatus != .member`. One stock file, +3 lines. Default-off. |

## Misc

| patch | description |
| --- | --- |
| ✅ `misc__clear-config` | shared-data keys 30/31/32 (`clearConfigSettings`, `hiddenChatsSettings`, `hiddenMessagesSettings`) added to `submodules/TelegramUIPreferences/Sources/PostboxKeys.swift`. Foundation all fork settings types consume. |
| ✅ `misc__branding` | rename app display name "Telegram" → "Cleargram" in `TelegramInfoPlist` (`CFBundleDisplayName` + `CFBundleName`) in `Telegram/BUILD`. Extensions keep "Telegram" (their `AppNameInfoPlist` unchanged). Bundle id stays `org.YOUR_BUNDLE_ID_HERE.Telegram` (changing it loses app-group data). |

## Planned (not from keetgram)

- `bugfix__send-duplicate-on-multi-tap` — fix duplicate message sends when tapping send
  multiple times under bad network (situational; investigate + debounce the send button
  while a send is in-flight).
- Cleargram settings panel expansion — add more `ClearConfig` toggles (currently has
  hideStories, hideAiFeatures, doubleTapDelay). See `docs/inugram-features.md`
  for the full candidate list.
- `misc__branding` expansion — Localizable.strings (user-visible "Telegram" strings),
  app icon, launch screen. See STATUS.md "Planned" for full scope.

### Pending wire-up (UI placeholder, no behaviour yet)

All have a disabled toggle in Cleargram Settings marked "(soon)". Wire-up in progress:

- `blockCloudDrafts` — don't sync drafts to cloud (keep local-only). From patchgram/yukigram.
- `showForwardedTime` — show original timestamp in forwarded message header. From yukigram.
- `noSelectionCap` — lift the 100-message selection cap + auto-chunk deletes. From inugram.
- `stripTrackingParams` — strip utm/fbclid/gclid from URLs on send/paste/copy. From inugram.
- `replacePreviewLinks` — rewrite twitter.com/x.com→fixupx/fxtwitter, bsky.app→fxbsky.app
  for link previews. From yukigram/inugram.
- `confirmInternalLinks` — confirmation alert before opening tg:// / t.me links. From inugram.
- `hideSponsoredMessages` — suppress sponsored posts in channels. From yukigram/patchgram.
- `hideStarReactionButton` — hide the Star (paid) reaction button in the reaction bar.
  From yukigram.
- `hideStarReactionCount` — hide the Star reaction counter on messages. From yukigram.
- `hideSimilarChannels` — hide "Similar Channels" panel on channel join. From yukigram.
- `warnPollsRevote` — warn before revoting in polls that forbid revoting. From yukigram.
- `showPackOwner` — show the owner of a sticker/emoji pack on the pack info screen. From yukigram.
- `timeOnServiceMessages` — render timestamp on service messages ("X added Y"). From yukigram.

### Pending implementation (not yet in UI)

**Visual / chat list (from Swiftgram):**
- `showTabNames` — show text labels under tab bar icons (height 56 vs 40). Default-on (matches stock). Sites: `TabBarComponent.swift` (5 sites: barHeight, containerSize, itemHeight, lensSelection, title alpha) + `TabBarContollerNode.swift` (title view alpha).
- `compactChatList` — compact chat list rows (smaller avatar /1.5, tighter spacing /1.5). Sites: `ChatListItem.swift` (avatarDiameter at L2026 + L2568, itemHeight at L4053).
- `chatListLines` — configurable number of preview lines in chat list (1-3). Applied indirectly via `SGCompactMessagePreviewLayout` wrapper in Swiftgram; not yet ported (needs the wrapper).
- `compactFolderNames` — shorten folder tab names. Sites: `ChatListFilterTabContainerNode.swift` (minSpacing /2.5) + `HorizontalTabsComponent.swift` (sideInset /2.0).
- `allChatsTitleLengthOverride` — truncate "All Chats" title length. (not yet ported)
- `allChatsHidden` — hide the "All Chats" folder tab entirely. Sites: `ChatListController.swift` (L409 — filter out .all before isFirstFilter check) + `ChatListControllerNode.swift` (L597 — filter out .all in panGesture). TelegramCore site skipped (can't import TelegramUIPreferences).
- `hideTabBar` — hide the bottom tab bar completely. Sites: `TabBarContollerNode.swift` (tabBarHidden init) + `ChatListController.swift` (3 sites: reordering show/hide) + `ChatListFilterTabContainerNode.swift` (2 sites: height/size override to 46.0) + `PeerInfoScreen.swift` (3 sites: updateIsTabBarHidden + back button in settings).
- `wideTabBar` — wider tab bar layout (no width reducer). Site: `TabBarComponent.swift` (skip widthReducer when on).
- `tabBarSearchEnabled` — search button in tab bar. Sites: `TabBarComponent.swift` (skip 48.0 width reduction when on) + `TabBarContollerNode.swift` (nil search when off). **Fallback needed:** when user disables this, search should appear elsewhere (e.g. navigation bar button or in the ⋮ menu) so search is never fully lost. RESEARCH: how stock Telegram handles search when tab bar is hidden (e.g. iPad layout).
- `bottomTabStyle` — bottom tab style variant. (not yet ported)
- `wideChannelPosts` — channel posts at full screen width (no margin). Sites: `ChatMessageBubbleItemNode.swift` (L2011 — set tmpWidth = baseWidth + needsShareButton = false) + `ChatMessageInteractiveMediaNode.swift` (L974 — widen maxDimensions for broadcast images).
- `hideChannelBottomButton` — hide the bottom bar in channel preview (mute/join/etc). NOT PORTED — requires adding `forceHideChannelButton` parameter to `inputPanelForChatPresentationIntefaceState` in `ChatInterfaceStateInputPanels.swift`.
- `disableGalleryCamera` — remove the camera tile from the attachment photo picker.
- `disableGalleryCameraPreview` — disable the live camera preview animation in the picker.
- `disableStoryCameraSwipe` — disable the swipe-left-from-chat-list gesture that opens the story camera.
- `disableContactsTab` — hide the Contacts tab in the bottom tab bar.
- `disableCallsButton` — hide the call button in chat header and profiles.

**iPad layout (iOS-only):**
- `enableMultiColumnLayout` — force iPad-style multi-column (chat list + chat side-by-side) on iPhone. Complex — forces `widthClass: .regular` which touches many layout paths. WIP, may break sheets/navigation.

**Chat (from inugram):**
- `admin-logs-improvements` — **COPY FROM INUGRAM** (`051b7298`). In Recent Actions (admin log): show all lines of "original message" (currently truncated to 12 lines via `ChatMessageAttachedContentNode`), inline text diff view for edited messages. Needs inugram's `WordDiff.kt` + `ChatMessageEventLogDiffContentNode` sibling. Both `prev.text` + `message.text` available at `ChatRecentActionsHistoryTransition.swift:535` (`.editMessage(prev, message)` case).
- `sticker-save-to-photos` — save sticker to Photos (as image) via long-tap / context menu on sticker messages. Stock has "save to files" (music only) but not "save to Photos" for stickers. iOS needs `PHPhotoLibrary` write + `NSPhotoLibraryAddUsageDescription` permission (already in Info.plist). Gate `if ClearConfig.saveStickerToPhotos` in `ChatInterfaceStateContextMenus.swift` near View Sticker Pack item (~L1939). Render sticker via `chatMessageSticker(account:userLocation:file:small:false,fetched:true)` (StickerResources.swift:264) → `UIImage` → `PHAssetCreationRequest.forAsset().addResource(with: .photo, data:, options: nil)`. Stock `saveToCameraRoll(...)` (SaveToCameraRoll.swift:100) has the PHPhotoLibrary write pattern; `DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), ...)` (line 147) handles the permission prompt.
- `collapse-long-messages` — collapse very long text messages to a few lines with an expand-on-tap toggle. Touches `ChatMessageTextBubbleContentNode.swift` layout — change `maximumNumberOfLines` (currently `0` = unlimited for non-preview at L684) when collapsed; bubble height follows automatically from `textLayout.size` → `boundingSize` (L782). Tap handling via `tapActionAtPoint(_:gesture:isEstimating:)` (L1142) returning `.custom(() -> Void)` (ChatMessageBubbleContentNode.swift:168). Stock has truncation pattern at L635-669 (preview-mode `Conversation_ReadMore` token); Story caption (`StoryContentCaptionComponent.swift`) has full collapse/expand template (L704/716 layouts, `expand()`/`collapse()` at L372/391). Block-collapse toggle pattern via `requestToggleBlockCollapsed` (L166-176) is the canonical "toggle → `requestMessageUpdate` → relayout" loop.

**Network (from inugram `abe0373`):**
- `faster-file-load` — bump download chunk size to 512KB + max 8 parallel requests; bump upload chunk min to 512KB. Ported from inugram `abe0373` (`FileLoadOperation.java` `downloadChunkSizeBig = 1024 * 512` + `FileUploadOperation.java` `minUploadChunkSizeBoost = 512`). iOS equivalents: `FileLoadOperation`/`FileUploadOperation` in `submodules/TelegramCore/Sources/Network/` — grep for `downloadChunkSize` / `uploadChunkSize` / `maxDownloadRequests`. May improve throughput, may hurt non-Premium users. Default-on in inugram.

**Privacy (from inugram `77f42f7` paranoia mode):**
- `paranoia-mode` — **COPY FROM INUGRAM** (`77f42f7`). Hide selected peers from more surfaces when paranoia mode is on. Sites: contacts list (`ContactsController`), call log (`CallLogActivity`), share sheet (`ShareAlert`), stories (`StoriesController`), search adapters, app icons selector. Helper: `ParanoiaHelper.isHidden(account, peerId)` / `.filterContacts(account, list)` / `.anyHidden(account, ids)`. iOS analog: cleargram already has `HiddenChatsSettings` (shared-data key 31) — paranoia mode would gate the same hidden-peer set across `ContactsController`-equivalent, `CallListController` (recent calls), `ShareController`, story grids, search. Big surface — likely several `feature__paranoia-*` patches. Closely related to existing `feature__hidden-chats` (just extends the hidden-peer filter to more call sites).

**Media (iOS-only):**
- `video-circle-audio-source` — pick audio source (built-in mic / Bluetooth / external USB) while recording a video message ("кружок"). Stock uses the default audio input only. Touches `submodules/Camera/*` recording pipeline + a UI control during recording (or pre-record picker). May need `AVAudioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])` + route picker (`AVRoutePickerView`) or a custom mic picker. Investigate `Camera` submodule recording entry point.
- `video-quality-original-toggle` — add an "Original" option in the video quality selector (chat attachment → send-as-video) that skips re-encoding and sends the file as-is. Stock always re-encodes via `MediaEditorScreen` / `EditingState`. Touches the quality picker (search for `VideoQualitySettings` / `videoQuality` in `submodules/TelegramUI/`) and the encoding path in `MediaEditorScreen.swift` (L8345+ has a `saveToPhotos` closure nearby — encoding is `ExportSetup` / `AssetExportContext`). iOS-only, no Android analogue in inugram.
- `send-video-as-circle` — send a regular video as a video message (кружок). Stock only records circles via camera; this would convert a gallery video to a round video message. Touches the attachment/share flow + `MediaEditorScreen` (crop to circle) + `VideoMessagesRecorder` / recording pipeline. Medium-high complexity — needs re-encoding to round crop + message type conversion.

**Sticker creation:**
- `flat-sticker-corners` — option to create stickers WITHOUT rounded corners (currently hardcoded 1/8 width radius). Three gate sites: (1) `MediaEditorComposer.swift:138` (video sticker export mask) + `:249` (image sticker export mask) — both call `roundedCornersMaskImage(size:)` (L42, hardcoded `cornerWidth: size.width / 8.0`) when `values.isSticker`; replace with existing `rectangleMaskImage(size:)` (L53) when toggle on. (2) `StickerOutlineRenderPass.swift:128` — the white outline border also uses rounded-rect mask (`cornerRadius = floor(1080*0.97)/8.0 - outlineWidth`); gate for square outline. (3) Optional cosmetic: editor UI overlay `MediaEditorScreen.swift:6549/6559/6562` (`stickerFrameWidth / 8.0`). `ClearConfig.flatStickerCorners`, default-off. Note: this is about the sticker's outer shape, NOT the cutout contour (Vision subject extraction) — cutout stays as-is, only the rectangular crop gets square corners instead of rounded.

**Channel:**
- `show-channel-post-author` — when a user sends a message "as a channel" in a regular chat (send-as-channel), reveal the real user behind the channel identity. Stock shows only the channel name as sender. Telegram API exposes this: message has `from_id` (real sender) vs `sender_id`/`peer_id` (channel). Touches `ChatMessageBubbleItemNode` author/forward header rendering + `EngineMessage.author` field. Low-medium complexity if API surfaces `from_id` on incoming messages.
- `hide-channel-join-requests` — hide/disable visibility of new join requests to channels you admin. Stock shows join request notifications in chat list / chat header. Touches `ChatListControllerNode` join-request badge + notification handling in `TelegramCore`.

**Search:**
- `search-by-user-id` — search messages in a group/chat by author user-id, bypassing the "hidden members" restriction. When a group hides its member list, Telegram's in-chat search (`@username` filter) breaks — the server refuses to resolve usernames of non-members. This feature adds a "search by user id" entry point (manual numeric id input, or a list of known authors derived from already-loaded messages) and runs `messages.search` with `from_id` set to the target peer. **Hybrid approach:** (1) Try `context.engine.messages.searchMessages(location: .peer(peerId, fromId: targetId, ...))` — server-side search with `from_id` may work even when members are hidden (server filters by peer id, not member-list visibility). (2) Fallback: local filter of already-loaded history by `message.authorId == targetId` in Postbox, with progressive load + progress UI if the chat isn't fully cached. **RESEARCH NEEDED:** verify whether `messages.search` with `from_id` actually works for groups with hidden members (server may still reject if the requester can't see the target peer — needs `accessHash`). If `accessHash` is required, the local cache may hold it for peers that have appeared in the chat history; otherwise the bare-id path (`tg://user?id=`) may need to be used to resolve + cache the peer first. Touches: `ChatHistorySearchContainerNode` (UI for id input / author picker), `SearchMessages.swift` (already passes `fromId` to `Api.messages.search` — may just work), new fork file `ClearUserSearch.swift` for the hybrid logic.

**Media player:**
- `show-audio-format-bitrate` — display audio format (codec: MP3/AAC/FLAC/OPUS) and bitrate in the music player. Touches the audio player UI (search for `AudioPlayerScreen` / `MediaPlayer` / `MediaPlayerDisplay` in `submodules/TelegramUI/` + `submodules/MediaPlayer/`). Format info available from `TelegramMediaFile.mimeType` + resource size/duration math. Display in the player's info panel (track title area).

**Debloat (Premium/Stars/Gifts):**
- `debloat__hide-premium-stars-gifts` — hide Premium upsell, Stars balance, Gifts,
  collectibles, boosts and related monetization UI. Separate from `hideAiFeatures`.
  Inspired by patchgram's "Disable Premium, Stars, TON & Gifts" (its subpatches: app config
  block, Premium UI, Gifts, paid reactions, emoji statuses/effects, Stars/TON/collectibles,
  boosts). See `docs/grey-features.md` for adjacent anti-features.
- **Crypto-bullshit debloat** — TBD, discuss scope separately.

**Visual / UI:**
- `liquidGlassStyle` — option to choose between native iOS Liquid Glass (on supported devices), a fake/emulated glass effect (for older devices), or disabled (legacy solid). Native Liquid Glass is iOS 26+ only (`UINavigationBar`/`UITabBar` glass API); needs detection of OS version + device capability. Touches `TabBarComponent`, `NavigationBarComponent`, possibly `GlassBackgroundComponent`. RESEARCH NEEDED: which iOS 26 APIs expose the native glass effect, whether `GlassBackgroundComponent` already wraps them, and how to fall back gracefully on older iOS.
- `fontSizeOverride` — user-adjustable font size / DPI scale in Cleargram Settings (independent of system Dynamic Type). Apply via a multiplier on `itemListBaseFontSize` / `baseDisplaySize` consumed throughout chat list + chat bubbles. Must not break layout — clamp to safe range (e.g. 0.85–1.3) and test forum rows, tab bar, context menus, settings rows. RESEARCH: stock already reads `presentationData.fontSize` everywhere — can we just override the value at the source (`PresentationData.fontSize`) rather than patching every call site?
