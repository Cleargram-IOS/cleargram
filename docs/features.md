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

## Debloat

_(none yet)_

## Debloat

| patch | description |
| --- | --- |
| ✅ `debloat__hide-ai-features` | hide all AI features behind `ClearConfig.hideAiFeatures` toggle (default-off). Gates: summarize button on messages (`ChatMessageBubbleItemNode`), AI compose button in legacy and new Text Field v2 input panels (`ChatTextInputPanelNode`, `MessageInputPanelComponent` via `isAIEnabled` flag, `AttachmentTextInputPanelNode`, `LegacyMessageInputPanel`), AI button in `RichTextAttachmentScreen`. 12 stock files. UI toggle in Settings → Debug → Cleargram Settings. `ClearConfig.start()` called from `AppDelegate` at launch. |

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
  hideStories, hideAiFeatures, doubleTapDelay, animationSpeed). See `docs/inugram-features.md`
  for the full candidate list.
- `misc__branding` expansion — Localizable.strings (user-visible "Telegram" strings),
  app icon, launch screen. See STATUS.md "Planned" for full scope.
