# Cleargram Agent Guide

Cleargram is a **patchset**, not a fork. `worktree/` is a clone of
`TelegramMessenger/Telegram-iOS` pinned to a specific commit (`upstream-commit`), on top of
which stgit applies patches from `patches/`/`series`. Patches are an export of the stgit
stack, not the source of truth. Edits go **in `worktree/`**, the user exports
(`scripts/export`).

`docs/features.md` is the user-facing list of features/bugfixes. Keep it in sync: when
adding/removing/materially changing a patch, update `docs/features.md` in the same changeset.

---

## Golden rules (never violate)

1. **Edit `worktree/` directly.** Never hand-edit `patches/*.patch` or `series` — they're
   exports.
2. **Don't run `stg`/`git`** unless explicitly asked. Read-only `stg -C worktree top` /
   `stg -C worktree show <name>` is fine. `stg export`/`refresh`/`new`/`rebase` — only on
   user request.
3. **Stock patches stay tiny.** Only guard/wiring/hooks/field-visibility. Real logic lives
   in fork files (new `.swift` next to stock, or `src/swift/ClearGram/`). A patch that only
   touches `src/**` is usually wrong.
4. **Default-off = stock-identical behavior.** Every behavior change gated behind
   `ClearConfig.<TOGGLE>.value`. Verify **every** call site is gated.
5. **Check if stock already does it** first. Lite Mode / existing experimental settings
   often cover it. Tell the user, don't silently re-implement.
6. **Confirm bug repro on clean upstream** (in `worktree/` on `upstream-commit` without
   patches) before treating a visual/behavioral issue as a patch regression.
7. **No renames in stock. No removing stock imports** (except `ClearGram.*`).
8. **Prefer data-layer patches over UI-layer.** One hook in a controller beats fifteen in
   views.
9. **Never touch `MessagesController`-equivalents / Postbox protocols directly** — use
   `TelegramEngine` facades. (Upstream Telegram-iOS is mid Postbox→Engine refactor — see
   `worktree/CLAUDE.md`.)
10. **Don't touch stock DB schema.** Fork state goes through `accountManager` shared-data
    keys (see `HiddenChatsSettings`).
11. **No LSP.** SourceKit/IDE diagnostics don't work here — ignore "No such module" noise.
    Verify by building (see `docs/build-codesigning.md`); a Bazel build is slow but allowed.
12. **`print(...)` for debug logging** in Swift, not stock loggers.
13. **No patch may violate the Telegram API ToS or the Apple guidelines.** See
    "Compliance" below. If a requested feature does, say so and stop — don't implement it
    behind a toggle and don't implement a "lite" version of it.

---

## Compliance — Telegram API ToS & Apple guidelines

**Features that violate the Telegram API Terms of Service or the Apple App Review
Guidelines are not accepted into this patchset.** Not as an opt-in toggle, not default-off,
not "just for me". A toggle does not launder a violation: the code still ships in the
binary and the client still misbehaves once it's on. When a request lands in this
territory, report it to the user with the specific clause and propose the nearest
compliant alternative instead of quietly building it.

### Telegram API ToS (https://core.telegram.org/api/terms) — hard limits

| clause | what it means for a patch |
| --- | --- |
| "If an app allows accessing content from Telegram channels, it must include support for official sponsored messages … and may not interfere with this functionality" | **Hard violation, no exceptions.** Anything that hides channel ads, the promoted/PSA chat (`ChatListAdditionalItem.promoInfo`) or suppresses the sponsored view/click reporting calls is out — this is the clause Telegram actually enforces (notice → `api_id` cut in 10 days, which kills the build for everyone). A default-off toggle does not launder it — the code still ships in the binary. |
| no "ghost mode" | Don't block read receipts, typing status, online/last-seen, or defeat self-destructing messages / screenshot notifications. Hiding a chat *locally* (`feature__hidden-chats`) is fine — it doesn't lie to the server. Faking "unread" upstream is not. |
| no acting on the user's behalf without consent | No auto-join, auto-read, auto-reply, background account actions the user didn't trigger. |
| own `api_id`, disclosure, naming | Keep the api id/hash out of the stack (see `misc__build-config`), never name the app "Telegram\*" without an "Unofficial" prefix, and never ship Telegram's official logo as the app icon (`misc__app-icon`). |
| no training ML models on API data | Rules out any "export my chats to feed a model" patch. |

### Apple App Review Guidelines — the ones this app touches

| guideline | what it means for a patch |
| --- | --- |
| **1.2 User-Generated Content** — apps must keep "a mechanism to report offensive content" and "the ability to block abusive users" | Removing the **Report** action is a review risk. `ClearConfig.hideContextMenuReport` (in `feature__context-menu-toggles`) does exactly that; it survives only because the app isn't shipped through App Review today. Don't add more patches that remove report/block entry points. |
| **3.1.1 In-App Purchase** | Never unlock Telegram Premium functionality client-side. Building an *independent* implementation (e.g. voice transcription with Apple's on-device `Speech` framework) is fine — it isn't Telegram's paid feature, just a parallel one. Flipping a `isPremium` flag, faking limits or bypassing Stars is not. |
| **5.2.1 Intellectual property** | Telegram-iOS is GPLv2 — the fork itself is fine — but Telegram's name, logo and branding are not licensed. Keep branding distinct (`misc__branding`). |
| **2.5.1 private APIs / 2.3 accurate metadata** | No private-API tricks, no feature descriptions that don't match behaviour. |

**Distribution caveat:** cleargram is ad-hoc/sideload-signed today (`misc__build-config`), so
App Review never runs on it — Apple's guidelines are a self-imposed bar, not a gate. The
Telegram ToS *is* a live gate regardless of distribution: it binds the `api_id`, and losing
it kills the build for everyone.

### Clearly allowed

- **Hiding stock UI locally** (stories, AI buttons, Premium/Stars/Gifts upsell, chat-list
  notices, similar channels, join requests) — client-side presentation, no Telegram service
  is interfered with. Sponsored/promoted content is **not** in this bucket, see above. One
  self-imposed limit: never hide *security* notices (`reviewLogin`, `accountFreeze`,
  `setupPassword`, low-balance-before-cutoff) — that's a user-safety call, not a ToS one.
- **Reading more than the official client shows** (peer ids, DC, registration month, audio
  format) — all of it comes from fields the API already sent us.
- **Local-only storage changes** (blocking cloud drafts, extending the local recent-sticker
  list) — they only change what *this* client keeps.

---

## Upstream architecture — critical facts

### submodules/* are NOT git submodules

`.gitmodules` has only ~13 real git submodules (external libs: `rlottie`, `tgcalls`,
`webrtc`, `dav1d`, `rules_apple`, `rules_swift`…). The other `submodules/*`
(`TelegramUI`, `TelegramCore`, `Postbox`, `DebugSettingsUI`, `ChatListUI`, `Camera`…) are
**regular folders in the main repository**, not git submodules.

That's why stgit patches edit them in a single tree — patchset works just like on Android.
External submodules are touched only if a feature genuinely requires editing the lib (rare).

### Bazel, not Gradle

Every new `.swift` file must be registered in `BUILD.bazel` (or the submodule's `BUILD`).
This is the iOS analogue of inugram's `misc/` patches — fork-code registration via a patch.
Convention: put fork files under `Sources/ClearGram/` inside an existing submodule and
register them in its `BUILD`.

### Postbox → TelegramEngine (in progress)

Upstream is actively migrating from `import Postbox` to `TelegramEngine` facades (see
`worktree/CLAUDE.md` and `worktree/docs/superpowers/postbox-refactor-log.md`). When fork
code needs data:
- **Prefer `TelegramEngine`** facades (`context.engine.data`, `context.engine.messages`…).
- **Never typealias `Postbox`, `Account`, `MediaBox`** — umbrella types.
- **Don't substitute `Any`/`AnyObject`** for Postbox protocols (`Media`, `Peer`, `Message`).
  Use `EngineMedia`/`EnginePeer`/`EngineMessage`.
- If no facade covers the use site — keep `import Postbox` and flag it for a future facade.

### View frame ownership

A view doesn't control its own `frame` — the parent/layout system does. Don't write
`self.frame = …` from `update(...)`/`apply(...)` of a reusable component. Parent positions,
child lays out against `self.bounds`.

### ChatHistoryListNode — composition, not inheritance

`ChatHistoryListNodeImpl` composes `ListViewImpl` (π-rotation stays on the wrapper, child
gets identity transform). Don't assume `supernode`-chain depth — item nodes are one level
deeper than they appear. (Details in `worktree/CLAUDE.md`.)

---

## Patch groups & naming

Format: `group__name` → `patches/<group>/<name>.patch`. Commit subject = a short human
sentence (`Add hidden chats`).

| group | when |
| --- | --- |
| `bugfix` | fixes an upstream bug |
| `feature` | adds user-facing capability (qol, ui, customization) |
| `debloat` | only removes/toggles-off stock behavior |
| `hooks` | thin hooks for fork code, no visible effect on their own |
| `misc` | build, branding, infra |

`debloat` vs `feature`: only *removes* stock → `debloat`. Adds new capability → `feature`.

`hooks/` vs normal patch: if >1 future patch will wire into this stock surface → `hooks/`.
One-off for a single feature → keep inside the `feature/` patch.

---

## Where fork code lives

| case | where |
| --- | --- |
| Bugfix in a specific stock class | fix it **inline in that file** (like `EditTextCaption` in inugram). Don't detour through a helper. |
| Helper of 5–7 lines | inline in the patch |
| Larger logic | new `.swift` in `src/swift/ClearGram/<SubmoduleName>/`, **synced** (copied) into `worktree/submodules/<SubmoduleName>/Sources/ClearGram/` by `pnpm sync` |
| Cross-cutting feature (several submodules) | a fork file in the submodule that owns the area (e.g. settings types in `TelegramUIPreferences`, management UI in `DebugSettingsUI`) |

Fork file/symbol naming convention: prefix `Clear` (e.g. `ClearConfig`,
`HiddenChatsSettings`, `ClearHooks`).

### Fork source sync (copy, not symlink)

Unlike inugram (where `src/kotlin` is symlinked into the Gradle project and Gradle follows
it), **Bazel sandboxes its workspace (`worktree/`) and does not follow symlinks pointing
outside it.** So fork Swift code is **copied**, not symlinked:

- Edit fork code in `src/swift/ClearGram/<Submodule>/Foo.swift` (versioned in the cleargram repo).
- `pnpm sync` (or `pnpm setup`) copies it into `worktree/submodules/<Submodule>/Sources/ClearGram/Foo.swift` as a real file.
- The copied dir is git-excluded (`.git/info/exclude`), so `git status` stays clean and the patch doesn't carry the fork file — only the stock wiring + BUILD deps.
- The submodule's `BUILD` uses `glob(["Sources/**/*.swift"])`, so the copied files are picked up automatically; only new **deps** (e.g. `ItemListPeerItem`) need a patch hunk.
- Convention: edit in `src/swift/ClearGram/`, then `pnpm sync`. Don't edit the copied file in `worktree/` directly — it'll be overwritten on the next sync.
- **One generated file:** `ClearBuildInfo.swift` (upstream version + pinned upstream commit +
  cleargram commit, shown at the bottom of Cleargram Settings). It is checked in like any other
  fork source, but with placeholder values — `writeBuildInfo` (`scripts/lib.ts`) overwrites the
  worktree copy with the real ones at the end of `linkForkSource`, i.e. *after* the copy loop
  that just laid the placeholder down. The placeholder is what keeps a sync that didn't run
  from breaking the build. Keep build-time values (timestamps) out of it — it's a Bazel input,
  so it should only change when the pin or the commit does.
- **Dirty builds are identified, not just flagged:** a build off an uncommitted tree gets a
  `+<id>` suffix (hash of the working-tree patch) and `pnpm sync` archives that patch as
  `build/dirty-stamps/<commit>+<id>.diff` — gitignored, and a directly appliable patch, so a
  build seen on a device can be reconstructed with `git apply`. **That archive is also the
  undo for a wiped working tree** — if uncommitted work is lost, the newest stamp restores it
  (`git apply --exclude=<untracked file already on disk> build/dirty-stamps/<id>.diff`).
- **A new area needs an entry in `forkSyncDirs` (`scripts/config.ts`)** or `pnpm sync` never copies it and Bazel never sees the file. Current areas: `TelegramUIPreferences`, `DebugSettingsUI`, `TextFormat`, `ChatListUI`, `LegacyMediaPickerUI`, `MediaPickerUI`, `PeerInfoScreen` (→ `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ClearGram`, a nested target path — that works, `copyForkDir` mkdir -p's it and adds the git-exclude), `TelegramUI` (→ `submodules/TelegramUI/Sources/ClearGram`, for fork code that needs types only the app module has in scope — the media player state, for instance).

---

## `ClearConfig` pattern

Analogue of inugram's `InuConfig`, but in Swift:

```swift
public enum ClearConfig {
    public static let hideStories = ClearBool("hide_stories", default: false)
    public static let doubleTapDelay = ClearInt("double_tap_delay", default: 300)
}
```

- Storage: shared-data keys via `accountManager`
  (`applicationContext.sharedContext.accountManager`) — the same mechanism
  `HiddenChatsSettings` uses (shared-data key, NOT Postbox `PreferencesEntry`).
- Toggle via `ClearBool.value` (computed, reads from an in-memory cache that's kept in sync
  with shared-data).
- Default-off — every behavior gated: `if ClearConfig.hideStories.value { ... }`.
- Settings UI — Debug → "Cleargram Settings", or a dedicated section (planned).

### `ClearHooks` — the bridge into modules that can't import `TelegramUIPreferences`

Lives in `worktree/submodules/TelegramCore/Sources/State/SynchronizeChatInputStateOperation.swift`
(odd home, but established). Each entry is an `Atomic` mirrored from `ClearConfig.start(...)`.
Use it **only** when the call site genuinely can't reach `ClearConfig` — check the submodule's
`BUILD` deps first; most already have `TelegramUIPreferences`.

Current entries: `blockCloudDrafts`, `expandedMessageIds`, `fasterFileLoad`, `hideStories`
(read by `AvatarNode.setStoryStats`), `recentStickersLimit`. Adding one means two edits: the
`Atomic` here, and the matching `swap` in `ClearConfig.start`.

---

### `ClearStrings` — localization of fork-only UI

Lives in `src/swift/ClearGram/TelegramUIPreferences/ClearStrings.swift`. Every user-visible
string the fork adds goes through it:

```swift
ClearStrings.tr("Open link?", "Открыть ссылку?")   // English source, Russian translation
ClearStrings.plural(n, one: "параметр", few: "параметра", many: "параметров")
```

- **Language source:** `SharedDataKeys.localizationSettings` → `primaryComponent.languageCode`,
  mirrored into an `Atomic` by `ClearStrings.start(accountManager:)`, which `ClearConfig.start`
  calls. Same pattern as `ClearHooks` — call sites stay static, no `PresentationStrings`
  threading. Anything not `ru*` falls back to the English text.
- **Fork files** (`ClearSettingsController`, `ClearSettingsTransfer`, `QuietChatsController`)
  declare a file-private `private func L(_ en: String, _ ru: String)` shorthand and call it
  inline, so the text stays next to the row it belongs to.
- **Stock files patched by us** must NOT contain Russian text: add a named property to
  `ClearStrings` (`confirmOpenLink`, `contextMenuShowPackOwner`, `biometricReason*`…) and
  reference it, keeping the patch hunk a one-liner.
- **Don't translate:** stock strings (Telegram ships its own Russian, server-delivered — a
  locally added `Localizable.strings` key gets overwritten anyway), technical identifiers
  (`ID`, `DC`, codec names), and the `.cleargram` settings-file keys, which are format, not UI.
- Prefer an existing stock key when one fits (`strings.Conversation_ContextMenuCopy`,
  `strings.SponsoredMessageMenu_Hide`, `strings.Chat_NonContactUser_Registration`) — several
  patches already do, and those need no `ClearStrings` entry at all.

## Database / persistent state

- Stock DB schema and `LAST_DB_VERSION` are off-limits.
- Fork state — in `accountManager` shared-data keys (an integer namespace; stock occupies
  `<=22`, cleargram uses 30..39, see `scripts/config.ts` `clearSharedDataKeyRange`).
- Read/write via `applicationContext.sharedContext.accountManager.transaction { ... }` /
  `sharedData` with `ValueBoxKey`. See `HiddenChatsSettings.swift` for a worked example.

---

## Settings UI

- Debug Settings — simple start: add a section in `DebugController`. See
  `submodules/DebugSettingsUI/Sources/DebugController.swift`.
- `ClearSettingsController` (`src/swift/ClearGram/DebugSettingsUI/`) is the real home. The screen
  tree is **data** — `clearRootScreen()` at the bottom of the file. Row kinds: `.toggle`
  (`ClearToggle`, a `WritableKeyPath<…, Bool>` into `ClearConfigSettings` or
  `ExperimentalUISettings`, or `.soon(title:plan:)` for a disabled placeholder), `.select`
  (`ClearSelect`, a `WritableKeyPath<…, Int32>` + a fixed option list, rendered as a disclosure row
  with an action sheet), `.action` (`ClearAction`, a plain tappable row that runs code — used by
  the settings export/import), `.screen` (nested `ClearScreen`) and `.reset`. Adding an option is
  normally one line; the ids, equality and `ItemList` plumbing are generic.
- Any toggle that needs a restart → show a "Restart required" alert in the click handler.

---

## Stock hotspot files (frequently touched)

Paths under `worktree/`. **Files >2k lines — never Read top-to-bottom.** `rg` for the
symbol, then Read with `offset` + small `limit`.

| file | area |
| --- | --- |
| `submodules/TelegramUI/Sources/ApplicationContext.swift` | app context, accountManager |
| `submodules/TelegramUI/Sources/AppDelegate.swift` | app lifecycle, app-group |
| `submodules/TelegramUI/Sources/Chat/ChatController*.swift` | chat screen (many files) |
| `submodules/ChatListUI/Sources/Node/ChatListNode.swift` | dialogs list |
| `submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift` | search |
| `submodules/DebugSettingsUI/Sources/DebugController.swift` | debug settings (where fork menu goes) |
| `submodules/TelegramCore/Sources/TelegramEngine/*` | engine facades |
| `Telegram/BUILD` | app target, app_groups, entitlements |

---

## Java ↔ Kotlin gotchas (NOT APPLICABLE to iOS)

Inugram's Java/Kotlin doc isn't relevant here. Cleargram is Swift-only (plus Bazel `BUILD`
starlark). Swift-side gotchas:
- `@testable import` in tests is normal; not needed in non-test fork code.
- `public` for cross-submodule fork API; `internal` within a submodule.
- Guard goes **before** stock, early-return when fork takes over; for extension, fork runs
  **after** stock, without re-indenting the stock branch (rebases stay cheap).

---

## stgit workflow (user-initiated only)

Documented so you can answer questions / suggest commands. AI doesn't run these.

```bash
# create a new patch
stg -C worktree new feature__my-patch -m "Add my feature"
# ...edits in worktree/...
stg -C worktree refresh
pnpm export

# modify an existing patch (in-place)
# ...edits...
stg -C worktree refresh -p feature__my-patch

# modify an existing patch, floating to top (preferred for non-trivial changes)
stg -C worktree float feature__my-patch
# ...edits...
stg -C worktree refresh
pnpm export
```

`pnpm export` rewrites `patches/` + `series` from the stack. The user runs it.

"Which patch is top?" → `stg -C worktree top`.

---

## Common pitfalls (ported from inugram sessions to iOS)

1. **Running `stg`/`git`.** Don't. Read-only only.
2. **Hand-editing `patches/*.patch`.** It's an export. Edit `worktree/`, the user re-exports.
3. **Oversized stock patch.** Logic beyond guard + helper-call → fork file.
4. **Helper of 2–5 lines.** Inline. Extract only when >5–7 lines or genuinely reused.
5. **Replacing stock behavior instead of running after.** Stock stays; fork runs before (early
   return) or after, gated.
6. **Ungated fork behavior.** Default-off = stock. Verify every call site.
7. **Editing stock base classes.** Look for an existing extension hook first. Base-class edits
   rebase poorly.
8. **Direct `import Postbox` where an Engine facade exists.** Grep `TelegramEngine` first.
9. **Forgot `BUILD` when adding a new `.swift`.** Bazel won't pick it up automatically —
   register it in a patch.

---

## Fork tooling (`pnpm` scripts, not bash)

Tooling is in TypeScript (tsx), mirroring inugram exactly. AI does not run `pnpm` scripts
that mutate worktree state (`pnpm setup`, `pnpm export`, `pnpm rebase`) without explicit
user request. Read-only `pnpm find-patches <path>` is fine.

| script | purpose |
| --- | --- |
| `pnpm setup [--force] [--no-stgit]` | clone upstream into `worktree/`, init stgit, apply `series`, sync fork sources |
| `pnpm sync` | re-copy fork Swift sources (`src/swift/ClearGram/<area>/`) into the worktree — run after editing fork code |
| `pnpm export` | rewrite `patches/` + `series` from the stgit stack |
| `pnpm rebase <commit\|latest>` | rebase stgit stack onto a new upstream commit |
| `pnpm find-patches <path>` | list which applied patches touch a file |

Pre-commit (`scripts/ci/pre-commit.ts`) verifies `patches/` is in sync with the stgit stack
— skips with `SKIP_PATCH_CHECK=1` or `--no-verify`.

---

## Self-maintenance

When adding a new `ClearHooks` method, settings page, or shared `hooks/` patch — update this
file. Tribal knowledge rots.
