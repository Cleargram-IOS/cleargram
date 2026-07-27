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
    keys (like keetgram `HiddenChatsSettings`, shared-data key 23).
11. **No LSP, no local build.** Don't try to compile. Verification is the user's build
    command (see `docs/build-codesigning.md`).
12. **`print(...)` for debug logging** in Swift, not stock loggers.

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
`HiddenChatsSettings`, `ClearHooks`). Not `inu_` (that's inugram), not `Keet` (that's
keetgram).

### Fork source sync (copy, not symlink)

Unlike inugram (where `src/kotlin` is symlinked into the Gradle project and Gradle follows
it), **Bazel sandboxes its workspace (`worktree/`) and does not follow symlinks pointing
outside it.** So fork Swift code is **copied**, not symlinked:

- Edit fork code in `src/swift/ClearGram/<Submodule>/Foo.swift` (versioned in the cleargram repo).
- `pnpm sync` (or `pnpm setup`) copies it into `worktree/submodules/<Submodule>/Sources/ClearGram/Foo.swift` as a real file.
- The copied dir is git-excluded (`.git/info/exclude`), so `git status` stays clean and the patch doesn't carry the fork file — only the stock wiring + BUILD deps.
- The submodule's `BUILD` uses `glob(["Sources/**/*.swift"])`, so the copied files are picked up automatically; only new **deps** (e.g. `ItemListPeerItem`) need a patch hunk.
- Convention: edit in `src/swift/ClearGram/`, then `pnpm sync`. Don't edit the copied file in `worktree/` directly — it'll be overwritten on the next sync.

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
  (`applicationContext.sharedContext.accountManager`) — same mechanism as keetgram's
  `HiddenChatsSettings` (shared-data key, NOT Postbox `PreferencesEntry`).
- Toggle via `ClearBool.value` (computed, reads from an in-memory cache that's kept in sync
  with shared-data).
- Default-off — every behavior gated: `if ClearConfig.hideStories.value { ... }`.
- Settings UI — Debug → "Cleargram Settings", or a dedicated section (planned).

---

## Database / persistent state

- Stock DB schema and `LAST_DB_VERSION` are off-limits.
- Fork state — in `accountManager` shared-data keys (an integer namespace; keetgram uses 23
  = hidden chats, 24 = hidden messages — cleargram uses a separate range starting at 30, see
  `scripts/config.ts` `clearSharedDataKeyRange`).
- Read/write via `applicationContext.sharedContext.accountManager.transaction { ... }` /
  `sharedData` with `ValueBoxKey`. See `HiddenChatsSettings.swift` in keetgram as reference.

---

## Settings UI

- Debug Settings — simple start: add a section in `DebugController`. See `submodules/DebugSettingsUI/Sources/DebugController.swift`.
- Later — a dedicated `ClearSettingsController` (planned in `docs/features.md`).
- Any toggle that needs a restart → show a "Restart required" alert in the click handler.

---

## Porting features from keetgram — cookbook

Keetgram is **merge-based**, not a patchset: its master has 30k commits and has merged
`origin/master` forward. So a keetgram feature commit's *parent* is usually an older
upstream point than cleargram's pinned `upstream-commit`. The keetgram commit diff won't
apply to the pinned commit directly.

**Working method:** diff keetgram's *current master* against the pinned upstream commit for
just the stock files the feature touches. That net diff already accounts for upstream
drift (keetgram merged origin/master), so it applies cleanly to the pinned commit:

```sh
# from the keetgram repo
git diff <pinned-upstream-commit> master -- <stock files...> > /tmp/feature.patch
# then in cleargram/worktree
git -C worktree apply /tmp/feature.patch
```

The fork code files (new `.swift` in `submodules/.../Sources/`) are **not** taken from this
diff — they live in `src/swift/ClearGram/` and are synced via `pnpm sync`. Only the stock
wiring + BUILD deps come from the net diff.

Features chosen for the first branch:

| keetgram commits | cleargram patch | status |
| --- | --- | --- |
| `46252b040a` "oauth fix" | — | **not ported**: authored by Ilya Laktyushin (a Telegram dev), already in upstream `6ad963e5b6` |
| `76131c1ec7` + `c4650d972a` hidden chats + presets | `feature__hidden-chats` | ✅ ported (net diff against `6ad963e5b6`) |
| `f2e0edb417` hidden messages | `feature__hidden-messages` | 🔵 planned (depends on hidden-chats) |
| `4798e9fd8e` camera picker | `feature__camera-picker-video-messages` | 🔵 planned |

Cherry-pick from keetgram into worktree (user runs only). AI doesn't run git/stg — only
suggests commands.

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
