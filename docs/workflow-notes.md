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

### Disabled toggle = "(soon)" placeholder
New planned features get a disabled switch (`enabled: false`, title suffix "(soon)") so
the user sees the roadmap. Wire-up replaces the placeholder with a real `updated` closure +
removes "(soon)". Update `docs/features.md` "Pending wire-up" section in the same change.

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
1. Change `let` → `var` in the struct (Swiftgram does this — invasive, touches a shared type).
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

## Disk space budget
- Bazel execroot: ~36G (clearable via `bazel clean`)
- Disk cache: ~24G (20G GC cap in `.bazelrc`, don't delete)
- Xcode DerivedData: ~800M (clearable)
- Need ~20G free for a device build to succeed (sim is smaller).

## What NOT to do
- Don't `rm -rf` the disk cache to free space — `bazel clean` instead.
- Don't `uninstall` before `install` — overwrites in place, preserves login.
- Don't add fork `.swift` files <20 lines — inline in stock.
- Don't hand-edit `patches/*.patch` — edit worktree, user exports.
- Don't run `stg`/`git` unless asked.
- Don't assume a Swiftgram call site works without checking the property is `var` upstream.
