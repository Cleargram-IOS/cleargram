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
| ✅ `feature__camera-picker-video-messages` | front/back camera picker for video messages. Ported from keetgram `4798e9fd8e` (net diff against `6ad963e5b6`). Gated by `ClearConfig.videoMessageCameraSelection` (default-off); toggle in Cleargram Settings ▸ Media. The port originally added the flag to stock `MediaInputSettings` with a default of `true` and a hardcoded English row in Data & Storage — i.e. it changed press-and-hold on the round-video button for every user with no Cleargram toggle touched. Both stock files are now back at upstream state and the single call site in `ChatControllerLoadDisplayNode` reads `ClearConfig`. Build-verified. |
| ✅ `feature__biometric-confirmation` | Face/Touch ID prompt before destructive actions: delete chat (chat list swipe/menu + in-chat delete), clear history, logout. Three independent toggles (`biometricConfirmDeleteChat`, `biometricConfirmClearHistory`, `biometricConfirmLogout`), default-off. **Fail-closed:** once a toggle is on, the action runs only after a successful evaluation. The helper uses `LAPolicy.deviceOwnerAuthentication` directly (not `LocalAuth`, which is biometrics-only), so biometry lockout, denied Face ID permission and missing enrollment fall back to the device passcode instead of silently disabling the gate; a device with no passcode at all blocks the action. A fresh `LAContext` per call prevents a cached success from waving the next action through. Fork helper `ClearBiometricHelper.gate(reason:enabled:onFailure:onSuccess:)` in `src/swift/ClearGram/TelegramUIPreferences/` — `onSuccess` is deliberately **last** because every call site passes it as an unlabeled trailing closure and Swift matches those backwards. Stock wiring: gate wrappers via the `Impl`-split pattern (no call-site re-indent) in `ChatListController.schedulePeerChatRemoval`, `ChatController.deleteChat` + `beginClearHistory`, `LogoutOptionsController` logout action; no BUILD hunk (`LocalAuthentication` is an SDK framework, autolinked). Known gap: chat-list bulk delete (`toolbarActionSelected`) and chat-list Clear History (`beginClear`) are not yet gated. Inspired by inugram `7b92f5b`. |
| ✅ `feature__show-audio-format-bitrate` | display audio codec (MP3/AAC/OGG/FLAC/WAV/OPUS) and bitrate (kbps) in the music player subtitle. Extends `SharedMediaPlaybackDisplayData.music` with an optional `formatInfo: String?` parameter (signature change in `AccountContext` — touches 6 stock files: enum + == + 4 call sites + 2 consumer destructure sites). Fork helper `clearAudioFormatInfo(mimeType:size:duration:)` in `src/swift/ClearGram/TelegramUIPreferences/ClearAudioFormatInfo.swift`. Appended to the performer/artist subtitle in `OverlayAudioPlayerControlsNode` (gated by `ClearConfig.showAudioFormatBitrate`, default-off). |
| ✅ `feature__faster-file-load` | bump download/upload chunk sizes for faster file transfer. Download: large files use 1MB part size (up from 512KB) in `MultipartFetch`, non-story uses 512KB (up from 128KB) in `FetchV2`. Upload: `useLargerParts` path uses 512KB (up from 256KB), default uses 256KB (up from 128KB) in `MultipartUpload`. Gated by `ClearConfig.fasterFileLoad` (default-off) bridged into `TelegramCore` via `ClearHooks.fasterFileLoad` (`Atomic<Bool>`), synced from `ClearConfig.start()`. 4 stock files. Inspired by inugram `abe0373`. |
| ✅ `feature__profile-copy-name` | long-press the peer's display name in the profile header to copy it to clipboard. Adds a `UILongPressGestureRecognizer` to `titleNodeRawContainer` in `PeerInfoHeaderNode` (mirroring the existing username/phone long-press pattern), a `displayCopyNameContextMenu` callback, and wiring in `PeerInfoScreen` that shows a context menu with a "Copy" action + undo overlay. Always-on (purely additive — long-press on the name was a no-op in stock). 2 stock files. Inspired by inugram `13aaefb`. |
| ✅ `feature__copy-image-in-gallery` | "Copy" action in the "⋯" menu of the fullscreen image viewer — copies the full-size image to the clipboard. Stock only offers copy from the message context menu, and only when the message holds exactly one photo and no text; in the gallery every item is a single image, so the limitation disappears. Added to `contextMenuMainItems()` in `submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift`, inside the existing copy-protection guard (`!message.isCopyProtected() && !peerIsCopyProtected && paidContent == nil`), right after "Save Image". Fetches the original via `fetchMediaData` (same call the "Create Sticker" item uses), sets `UIPasteboard.general.image`, then shows the stock `.copy(text: Conversation_ImageCopied)` undo overlay. Gated by `ClearConfig.copyImageInGallery` (default-off); toggle in Cleargram Settings ▸ Media. 1 stock file (import + gated block); `GalleryUI` already deps on `TelegramUIPreferences`, so no BUILD hunk. |
| ✅ `feature__clear-settings-ui` | "Cleargram Settings" entry in `DebugController`, opening `ClearSettingsController` (fork file in `src/swift/ClearGram/DebugSettingsUI/`). Home for every `ClearConfig` toggle. |
| ✅ `feature__hide-stories` | hide the stories strip in the chat list (`ClearConfig.hideStories`) and disable the swipe-from-chat-list gesture that opens the story camera (`disableStoryCameraSwipe`). 1 stock file. |
| ✅ `feature__seconds-in-messages` | show seconds in message timestamps — `ClearConfig.secondsInMessages` in `TextFormat/DateFormat.swift`. |
| ✅ `feature__confirm-calls` | confirmation alert before placing a call, in `AccountContext.swift`. `ClearConfig.confirmCalls`. |
| ✅ `feature__double-tap-to-edit` | double-tap your own message to open the editor. `ChatController` + `ChatControllerInteraction`; delay configurable via `ClearConfig.doubleTapDelay`. |
| ✅ `feature__profile-id-dc` | show the peer's numeric id and datacenter in the profile (`showProfileId`, `showDC`), and hide the phone number in your own profile (`hidePhoneInSettings`). |
| ✅ `feature__context-menu-toggles` | individually hide Reply / Pin / Forward / Report / Select in the message context menu. 1 stock file, 5 toggles. |
| ✅ `feature__default-emojis-first` | put the standard-emoji tab first in `EntityKeyboard` instead of custom/recent. `ClearConfig.defaultEmojisFirst`. |
| ✅ `feature__scroll-next-channel` | disable the "scroll past the end → next channel" gesture. `ClearConfig.disableScrollToNextChannel`. |
| ✅ `feature__inline-reactions` | render reactions inline in the date/status row instead of a separate line. `ClearConfig.showInlineReactions`. |
| ✅ `feature__hide-sponsored` | suppress sponsored posts in channels. One gate in `ChatControllerNode.swift`. |
| ✅ `feature__disable-gallery-camera` | remove the camera tile from the attachment photo picker (`MediaPickerScreen.swift`). |
| ✅ `feature__flat-sticker-corners` | square instead of rounded corners when creating stickers — `MediaEditorComposer` export masks + `StickerOutlineRenderPass` outline. |
| ✅ `feature__forwarded-time` | show the original send time in the forwarded-message header. Touches the bubble/sticker/instant-video item nodes + `ChatMessageForwardInfoNode`. |
| ✅ `feature__block-cloud-drafts` | stop syncing drafts to the cloud (local-only). Gate in `SynchronizeChatInputStateOperation` via `ClearHooks.blockCloudDrafts`, since `TelegramCore` can't import `TelegramUIPreferences`. |
| ✅ `feature__sticker-save-to-photos` | "Save to Photos" for stickers in the message context menu, via the stock `saveToCameraRoll`. Animated stickers excluded. |
| ✅ `feature__collapse-long-messages` | collapse very long text messages with tap-to-expand. Expanded ids kept in `ClearHooks.expandedMessageIds`. |
| ✅ `feature__show-pack-owner` | "Show Pack Owner" in the "⋯" menu of a sticker pack — derives the owner id from the pack id and opens their profile. The owner `PeerId` is built with an explicit `CloudUser` namespace; the packed `PeerId(Int64)` initializer produced a garbage peer for every 64-bit user id. The bit arithmetic that extracts the id from the pack id is inherited as-is and unverified. |
| ✅ `feature__hide-similar-channels` | hide the "Similar Channels" block in the chat and in the profile. |
| ✅ `feature__hide-star-reaction` | hide the Star (paid) reaction button in the reaction bar. |
| ✅ `feature__url-cleaner` | strip tracking query params (`stripTrackingParams`) and rewrite hosts to preview-friendly frontends — x/twitter→fixupx, instagram→kkclip, tiktok→kktiktok, reddit→rxddit, bsky→fxbsky, pixiv→phixiv (`replacePreviewLinks`). Applies to the link-preview URL while composing and to "Copy" on a link — not to the sent text. Logic in `src/swift/ClearGram/TextFormat/ClearURLCleaner.swift`; host patterns are anchored so that e.g. `netflix.com` isn't mistaken for `x.com`. |
| ✅ `feature__hide-star-reaction-count` | hide the Star reaction counter on messages. |
| ✅ `feature__time-on-service-messages` | render a timestamp on service messages ("X added Y"). |
| ✅ `feature__warn-polls-revote` | confirmation alert before changing your vote in a poll. Fires only when a vote already exists and the new choice differs; the second tap passes through via an `Atomic<Set<MessageId>>` skip-set. Alert text is hardcoded English. |
| ✅ `feature__confirm-internal-links` | confirmation alert before opening `tg://` / `t.me` links (`OpenUrl.swift`). |
| ✅ `feature__visual-swiftgram` | Swiftgram-style visual toggles: tab bar (`hideTabBar`, `showTabNames`, `wideTabBar`, `tabBarSearchEnabled`), folder tabs (`compactFolderNames`, `allChatsHidden`) and full-width channel posts (`wideChannelPosts`). 12 stock files. **Not default-off:** the tab bar width reducer in `TabBarComponent.swift` is active unless `wideTabBar` is on, so with fewer than 4 tabs the bar is narrower than stock (÷1.25 for 3 tabs, ÷1.5 for 2, ÷1.75 for 1). Inverting it to `narrowTabBar` would restore stock-by-default. |
| ✅ `feature__compact-chat-list` | compact chat list rows — smaller avatar and tighter spacing (`compactChatList`), plus a reduced preview line count (`compactMessagePreview`, derived from `chatListLines != 3`). |
| ✅ `feature__settings-ui-fixes` | follow-ups for `hideTabBar`: back button in Settings and the chat-list entry point keep working when the tab bar is hidden. |
| ✅ `feature__disable-contacts-calls` | hide the Contacts tab (`disableContactsTab`) and the call button in profiles (`disableCallsButton`). |
| ✅ `feature__font-size-override` | font size override for messages in chats. In `PresentationData.swift` (`resolveFontSize(settings:)`), if `ClearConfig.fontSizeOverride` is enabled, forces `fontSize = .large` (19pt) for chat messages without changing system/list font sizes. UI toggle in Cleargram Settings ▸ Chat, wired with restart overlay prompt (`askForRestartImpl`). 1 stock file + fork settings UI. |

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
| ✅ `misc__app-icon` | new app icon — replaces the Icon Composer document (`Telegram.icon/icon.json` + assets). Icon only; the build settings it used to carry moved to `misc__build-config`. Carries the only binary hunk in the stack, which is why `pnpm setup` chokes on it on a clean machine (see `docs/build-codesigning.md`). |
| ✅ `misc__build-config` | build configuration for ad-hoc (ad-hoc) signing: the app group pinned to `group.<APP_GROUP>` in `Telegram/BUILD` + `AppDelegate.swift` (the service certificate never registers `group.<bundleId>`, and deriving it yields a black screen), plus `.bazelrc` with disk-cache GC limits and `--//Telegram:disableExtensions=True`. **No credentials:** `build-system/template_minimal_development_configuration.json` deliberately stays out of the stack — keep it as a local file marked `git update-index --skip-worktree`, otherwise `stg export` bakes api id/hash into the patch. |
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

- `noSelectionCap` — lift the 100-message selection cap + auto-chunk deletes. From inugram.

### Pending implementation (not yet in UI)

**Visual / chat list (from Swiftgram):**

Most of this group shipped in `feature__visual-swiftgram` / `feature__compact-chat-list` /
`feature__disable-contacts-calls` / `feature__disable-gallery-camera`. Still open:

- `chatListLines` — configurable number of preview lines in chat list (1-3). Applied indirectly via `SGCompactMessagePreviewLayout` wrapper in Swiftgram; not ported (needs the wrapper). Only the derived `compactMessagePreview` flag is wired.
- `allChatsTitleLengthOverride` — truncate "All Chats" title length. Toggle exists in the settings UI, no behaviour yet.
- `bottomTabStyle` — bottom tab style variant. (not yet ported)
- `disableGalleryCameraPreview` — disable the live camera preview animation in the picker.
- `tabBarSearchEnabled` fallback — when search is removed from the tab bar it disappears entirely; it should resurface elsewhere (navigation bar or ⋯ menu). RESEARCH: how stock handles search when the tab bar is absent (iPad layout).

**iPad layout (iOS-only):**
- `enableMultiColumnLayout` — force iPad-style multi-column (chat list + chat side-by-side) on iPhone. Complex — forces `widthClass: .regular` which touches many layout paths. WIP, may break sheets/navigation.

**Chat (from inugram):**
- `admin-logs-improvements` — **COPY FROM INUGRAM** (`051b7298`). In Recent Actions (admin log): show all lines of "original message" (currently truncated to 12 lines via `ChatMessageAttachedContentNode`), inline text diff view for edited messages. Needs inugram's `WordDiff.kt` + `ChatMessageEventLogDiffContentNode` sibling. Both `prev.text` + `message.text` available at `ChatRecentActionsHistoryTransition.swift:535` (`.editMessage(prev, message)` case).

**Network (from inugram `abe0373`):**

**Privacy (from inugram `77f42f7` paranoia mode):**
- `paranoia-mode` — **COPY FROM INUGRAM** (`77f42f7`). Hide selected peers from more surfaces when paranoia mode is on. Sites: contacts list (`ContactsController`), call log (`CallLogActivity`), share sheet (`ShareAlert`), stories (`StoriesController`), search adapters, app icons selector. Helper: `ParanoiaHelper.isHidden(account, peerId)` / `.filterContacts(account, list)` / `.anyHidden(account, ids)`. iOS analog: cleargram already has `HiddenChatsSettings` (shared-data key 31) — paranoia mode would gate the same hidden-peer set across `ContactsController`-equivalent, `CallListController` (recent calls), `ShareController`, story grids, search. Big surface — likely several `feature__paranoia-*` patches. Closely related to existing `feature__hidden-chats` (just extends the hidden-peer filter to more call sites).

**Media (iOS-only):**
- `video-circle-audio-source` — pick audio source (built-in mic / Bluetooth / external USB) while recording a video message ("кружок"). Stock uses the default audio input only. Touches `submodules/Camera/*` recording pipeline + a UI control during recording (or pre-record picker). May need `AVAudioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])` + route picker (`AVRoutePickerView`) or a custom mic picker. Investigate `Camera` submodule recording entry point.
- `video-quality-original-toggle` — add an "Original" option in the video quality selector (chat attachment → send-as-video) that skips re-encoding and sends the file as-is. Stock always re-encodes via `MediaEditorScreen` / `EditingState`. Touches the quality picker (search for `VideoQualitySettings` / `videoQuality` in `submodules/TelegramUI/`) and the encoding path in `MediaEditorScreen.swift` (L8345+ has a `saveToPhotos` closure nearby — encoding is `ExportSetup` / `AssetExportContext`). iOS-only, no Android analogue in inugram.
- `send-video-as-circle` — send a regular video as a video message (кружок). Stock only records circles via camera; this would convert a gallery video to a round video message. Touches the attachment/share flow + `MediaEditorScreen` (crop to circle) + `VideoMessagesRecorder` / recording pipeline. Medium-high complexity — needs re-encoding to round crop + message type conversion.

**Sticker creation:**

**Channel:**
- `show-channel-post-author` — when a user sends a message "as a channel" in a regular chat (send-as-channel), reveal the real user behind the channel identity. Stock shows only the channel name as sender. Telegram API exposes this: message has `from_id` (real sender) vs `sender_id`/`peer_id` (channel). Touches `ChatMessageBubbleItemNode` author/forward header rendering + `EngineMessage.author` field. Low-medium complexity if API surfaces `from_id` on incoming messages.

**Search:**
- `search-by-user-id` — search messages in a group/chat by author user-id, bypassing the "hidden members" restriction. When a group hides its member list, Telegram's in-chat search (`@username` filter) breaks — the server refuses to resolve usernames of non-members. This feature adds a "search by user id" entry point (manual numeric id input, or a list of known authors derived from already-loaded messages) and runs `messages.search` with `from_id` set to the target peer. **Hybrid approach:** (1) Try `context.engine.messages.searchMessages(location: .peer(peerId, fromId: targetId, ...))` — server-side search with `from_id` may work even when members are hidden (server filters by peer id, not member-list visibility). (2) Fallback: local filter of already-loaded history by `message.authorId == targetId` in Postbox, with progressive load + progress UI if the chat isn't fully cached. **RESEARCH NEEDED:** verify whether `messages.search` with `from_id` actually works for groups with hidden members (server may still reject if the requester can't see the target peer — needs `accessHash`). If `accessHash` is required, the local cache may hold it for peers that have appeared in the chat history; otherwise the bare-id path (`tg://user?id=`) may need to be used to resolve + cache the peer first. Touches: `ChatHistorySearchContainerNode` (UI for id input / author picker), `SearchMessages.swift` (already passes `fromId` to `Api.messages.search` — may just work), new fork file `ClearUserSearch.swift` for the hybrid logic.

**Media player:**

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
