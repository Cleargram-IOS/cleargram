# Workflow notes & gotchas

Hard-won knowledge from this session. Read before repeating mistakes.

## Build commands (cheat sheet)

### Device build (debug, signed for iPhone)
```sh
cd <cleargram>/worktree && \
./build-input/bazel-8.4.2-darwin-arm64 build Telegram/Telegram \
  --announce_rc --features=swift.use_global_module_cache --verbose_failures \
  --remote_cache_async --define=buildNumber=1 \
  --disk_cache=~/telegram-bazel-cache \
  -c dbg --ios_multi_cpus=arm64 --watchos_cpus=arm64_32 \
  '--@build_bazel_rules_swift//swift:copt=-j' '--@build_bazel_rules_swift//swift:copt=8' \
  --//Telegram:disableExtensions
```
Output: `bazel-bin/Telegram/Telegram.ipa`

### Simulator build
Same but `--ios_multi_cpus=sim_arm64` (drop `--watchos_cpus`), add `--//Telegram:disableProvisioningProfiles`.

### Install to device (overwrites, preserves login)
```sh
xcrun devicectl device install app --device <UDID> \
  <cleargram>/worktree/bazel-bin/Telegram/Telegram.ipa
```
NEVER uninstall first — `install` overwrites in place, data container (login/settings) preserved.

### Build timing budget
- Cold build (no cache): 30-60 min
- Warm (disk cache hits): 30-45 sec
- After editing 1-2 files: 5-15 min (recompiles dependent modules)
- After `bazel clean` + rebuild: ~45 sec (execroot empty, disk cache warm)
- Install to device: 10-15 sec

## Builds & device install

### Direct bazel vs Make.py
`Make.py` does NOT pass `--//Telegram:disableExtensions` (no `--bazelArguments` passthrough
for `//Telegram:` flags in this version). Invoke bazel directly for free-account device builds:

```sh
cd worktree && ./build-input/bazel-8.4.2-darwin-arm64 build Telegram/Telegram \
  --announce_rc --features=swift.use_global_module_cache --verbose_failures \
  --remote_cache_async --define=buildNumber=1 \
  --disk_cache=~/telegram-bazel-cache \
  -c dbg --ios_multi_cpus=arm64 --watchos_cpus=arm64_32 \
  '--@build_bazel_rules_swift//swift:copt=-j' '--@build_bazel_rules_swift//swift:copt=8' \
  --//Telegram:disableExtensions
```

Simulator: swap `--ios_multi_cpus=arm64` → `--ios_multi_cpus=sim_arm64`, drop `--watchos_cpus`.

### `bazel clean` vs disk_cache
- `bazel clean` clears **execroot** (~36G at `/private/var/tmp/_bazel_<user>/...`) but
  **disk_cache survives** (`~/telegram-bazel-cache`, ~24G). After `clean`, rebuild is
  ~45s (cache hits), not 14min cold.
- NEVER `rm -rf ~/telegram-bazel-cache` — throws away warm state, forces cold rebuild.
- Disk full (820MB free) → signing fails with misleading "No space left on device" in
  process-and-sign step. Run `bazel clean`, not `rm -rf disk_cache`.

### DerivedData corruption (sim↔device switch)
Switching from `Debug-iphonesimulator` to `Debug-iphoneos` (or back) leaves stale
`.swiftmodule`/framework files that fail to copy. Fix:
```sh
osascript -e 'tell application "Xcode" to quit'  # Xcode holds files open
chmod -R u+w ~/Library/Developer/Xcode/DerivedData/Telegram-*  # Bazel marks read-only
rm -rf ~/Library/Developer/Xcode/DerivedData/Telegram-*
```
The `chmod` is mandatory — Bazel stamps `r-xr-xr-x` on framework binaries, plain `rm`
gets "Permission denied".

### Install to device — DON'T uninstall first
`xcrun devicectl device install app --device <UDID> <ipa>` **overwrites in place** and
preserves the data container (login, account, settings). Calling `uninstall` first wipes
the data container → user logs out. Only uninstall when the bundle id changes or you hit
the free-profile app limit.

### Free Apple Developer account = max 3 apps per device
`devicectl install` fails with `MIInstallerErrorDomain error 13` listing the 3 installed
bundle ids. Must uninstall one (any non-Cleargram one) to make room. Free profiles expire
in 7 days — re-issue via Xcode (open the .xcodeproj, let it regenerate).

### Provisioning profile discovery
Bazel `local_provisioning_profile` symlinks BOTH:
- `~/Library/MobileDevice/Provisioning Profiles/` (legacy, usually empty)
- `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (Xcode 16+ location)

Profile found by `profile_name` + `team_id` match (newest wins). If `bazel build` says
"profile not found" but `ls` shows it exists → stale `@local_provisioning_profiles` repo
cache. Run `bazel sync --configure --enable_workspace` (Bazel 8 needs `--enable_workspace`).
Direct `bazel build //Telegram:Telegram_local_profile` verifies the profile resolves.

### `bazel sync` on Bazel 8
`bazel sync --configure` errors "WORKSPACE has to be enabled" → add `--enable_workspace`.
The repo uses MODULE.bazel (bzlmod), WORKSPACE is disabled by default in Bazel 8.

## Cleargram Settings UI

### `stableId` MUST be globally ascending
`ItemListControllerNode` asserts entries are sorted by `stableId` across ALL sections, not
per-section. Out-of-order IDs → `EXC_BREAKPOINT` crash on settings open. When adding an
entry, pick a `stableId` that fits the global ascending order of `entries.append` calls,
not just the section. Crash log signature: `_assertionFailure` in
`closure #10 in ItemListControllerNode.init`.

### Disabled toggle = `.soon` placeholder
A planned feature gets `ClearToggle.soon(title, plan)`, which is `.unimplemented` storage
rendered as a disabled switch with **the plan text as the row subtitle**. There is no
"(soon)" suffix on the title — an earlier version of this note said there was.
Wiring it up means replacing the whole row with a real `ClearToggle(title, .config(\.field))`,
and updating the "Pending wire-up" list in `docs/features.md` in the same change.

Two traps worth knowing, both hit on 2026-09-29:
- **A `.soon` row is a promise the user can see.** Six of them currently sit in shipped
  settings. Adding one costs nothing; leaving one there for months is a visible lie.
- **A field with a read site but no row is a warning, not an oversight — verify on a device
  before wiring it up.** This note previously said the opposite ("add the row"), and following it
  on 2026-09-29 broke two things in one build. `showInlineReactions` looked like a shipped feature
  missing its switch; switching it on removed reactions from messages entirely, because the patch
  only swaps upstream's unconditional `false` for the flag and the branch that unlocks is
  unfinished. `chatListLines` looked like the dead half of `feature__compact-chat-list`; the slider
  changed nothing observable. In both cases the missing row *was the finding* — somebody had
  already discovered the path does not work and left no note. **So: leave the row out, and record
  in `docs/features.md` why the field is inert.** A static audit can prove a field is unread; only
  a device can tell you whether reading it would help.
- **Withdrawing a row is not enough on its own.** A user who already switched the setting on keeps
  the stored `true` and now has no way back. Force the accessor to `false` in `ClearConfig` in the
  same change, with a comment naming what must work before the real read returns — that is what
  `showInlineReactions`, `compactMessagePreview` and `ClearDesign.useLegacy` all do now.

## Tooling traps

Each of these cost real time once. They live here rather than in a handoff note, which rots.

- **Fish mangles `git show "$VAR:path"`.** The variable swallows part of the path
  (`$PRE:submodules/TabBarUI/Sou` → garbage). Write the revision as a literal:
  `git show ebcd0557e5^:submodules/TabBarUI/Sources/TabBarNode.swift`.
- **`stg refresh` always with explicit paths.** Otherwise `.bazelrc` rides into the patch —
  `pnpm setup` keeps a managed disk-cache block in it, so it is permanently modified in the tree.
- **No git command that moves the branch.** A stray `git commit --amend` once desynced HEAD from
  the top of the stgit stack; recovering took `stg repair` + deleting the duplicate + `stg rename`
  + `stg edit -m`.
- **`pnpm export` used to write `local__*` patches into the repo.** Fixed 2026-09-29 in
  `scripts/export.ts` — they are machine-specific (dev signing, build flags) and
  `check-patches.ts` was already built on the assumption that they never reach `patches/`.
  `/patches/local/` is gitignored as a second line of defence.
- **A bulk in-place edit across two anchors will happily delete everything between them.** Two
  files were truncated this way on 2026-09-29 (one settings file lost 664 lines, `features.md`
  lost a whole section) because a search string matched an earlier occurrence than intended.
  Anchor on something unique, and check the line count before and after.
- **Never touch `self.layer` or `self.view` in an `ASDisplayNode.init`.** `ListView` builds its
  item nodes on a background queue (`ListMessageItem.nodeConfiguredForParams(async:)`), and
  `-[ASDisplayNode layer]` asserts off the main thread → `SIGABRT` the moment a row is created.
  A node built only by the player or a panel gets away with it because those run on main, so this
  surfaces the day the same node is reused in a list. Put sublayer setup in `didLoad()`, which is
  guaranteed on main, and have it call the same `updateLayers()` the layout path uses, since state
  can arrive before the node loads. Cost one crash on 2026-09-29, found in 5 minutes from the
  device crash log — that path is much faster than reasoning about it.

- **`~/.config/fish/config.fish` and `~/.zshrc`** each had a `PNPM_HOME` pointing at a different
  user's home, left by `pnpm setup`, which broke the pnpm installer. Removed; backups are
  `config.fish.bak-cleargram` / `.zshrc.bak-cleargram`.

## Fork source files

### New `.swift` in `Sources/ClearGram/` needs Xcode project regenerate
Bazel `glob` picks up new files automatically, but `rules_xcodeproj` (Xcode project) does
NOT on incremental — needs `generateProject` re-run (slow). For tiny helpers (<20 lines),
**inline in the stock file** instead of adding a fork file. Fork files are for
>20-line logic that's reused or too big to inline.

### `pnpm sync` only copies registered dirs
`scripts/config.ts` `forkSyncDirs` lists which `src/swift/ClearGram/<area>/` →
`worktree/submodules/<area>/Sources/ClearGram/`. Adding a new fork area requires
editing `forkSyncDirs` + running `pnpm sync`. Forgetting the config entry → fork file
never lands in worktree → "Cannot find symbol" build error.

## Swift gotchas

### `let` struct property can't be mutated via `var` binding
Upstream `EmojiPagerContentComponent.panelItemGroups` is `public let`. Doing
`var mut = emojiContent; mut.panelItemGroups = ...` fails ("Cannot assign to property").
Two fixes:
1. Change `let` → `var` in the struct — invasive, touches a shared type.
2. Use the factory method `withUpdatedItemGroups(...)` (cleaner, no struct mutation, no
   shared-type edit). **Prefer this.**

### `var` declared but never mutated → warning-as-error
`-warnings-as-errors` is on. `var x = y` where only `x.prop = ...` happens (not `x = ...`)
triggers "Variable was never mutated". Use `let` for the binding, `var` for the inner
collection: `let result; var groups = x.groups; groups.remove(...); result = x.with(...)`

## Crash log retrieval from device

```sh
UDID=<UDID>  # your device
xcrun devicectl device info files --domain-type systemCrashLogs --device $UDID | grep Telegram
xcrun devicectl device copy from --device $UDID --domain-type systemCrashLogs \
  --source "Telegram-YYYY-MM-DD-HHMMSS.ips" --destination /tmp/crash.ips
python3 -c "
import json, re
data = open('/tmp/crash.ips').read()
j = json.loads(re.split(r'\n(?=\{)', data.strip())[1])
ct = next((t for t in j['threads'] if t.get('triggered')), j['threads'][0])
print('Exception:', j.get('exception', {}))
for f in ct.get('frames', [])[:30]: print(' ', f.get('symbol',''), '+'+str(f.get('symbolLocation','')))
"
```

## Pre-build sanity sweep (when a build isn't possible)

Bazel needs tens of GB; these three checks need none, run in seconds, and between them catch the
failures that blind patches actually produce. Worth doing before every build, and the only
verification available when the disk is full.

**1. Syntax.** `swiftc -parse` resolves no modules, so it runs on any file standalone:

```sh
for f in $(find src/swift/ClearGram -name '*.swift'); do swiftc -parse "$f" || echo "FAIL $f"; done
# and the stock files the patches touch:
grep -h '^+++ b/' patches/*/*.patch | sed 's|^+++ b/||' | sort -u | grep '\.swift$' \
  | while read f; do (cd worktree && swiftc -parse "$f") || echo "FAIL $f"; done
```

This is not theoretical — it found a stray `}` in `ClearTrackCache.swift` that closed the class
right after its stored properties, leaving `init` at file scope. A guaranteed build break, invisible
to review because the brace looked like the end of a property block.

**2. Imports.** Collect the `public` symbols declared under `src/swift/ClearGram/<Module>/`, then
check every `Clear*` identifier a patch adds to a stock file against that file's `import` list.
**Strip trailing `//` comments first** — the fork's comments mention `ClearConfig` while explaining
why a call site uses `ClearHooks` instead, which is otherwise two false positives every run.

**3. BUILD deps.** Same symbol map, but check the nearest `BUILD`/`BUILD.bazel` above the file.
Expect hits that are not bugs: rules_swift propagates modules transitively, so a package depending
on `//submodules/TelegramPresentationData` can `import TelegramUIPreferences` with no dep of its
own. Before adding a hunk, compare against a package that already ships that pattern
(`ChatListFilterTabContainerNode` and `TabBarComponent` both do) — if the transitive path matches,
there is nothing to fix.

What none of this catches: type errors, wrong argument labels, missing protocol conformances,
`-warnings-as-errors` warnings. It narrows the first build's failures, it does not replace it.

## Disk space budget
- Bazel execroot: ~36G (clearable via `bazel clean`)
- Disk cache: ~24G (40G GC cap in `.bazelrc`, don't delete)
- Xcode DerivedData: ~800M (clearable)
- Need ~20G free for a device build to succeed (sim is smaller).

## What NOT to do
- Don't `rm -rf` the disk cache to free space — `bazel clean` instead.
- Don't `uninstall` before `install` — overwrites in place, preserves login.
- Don't add fork `.swift` files <20 lines — inline in stock.
- Don't hand-edit `patches/*.patch` — edit worktree, user exports.
- Don't run `stg`/`git` unless asked.
