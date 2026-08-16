# Build & Codesigning — Cleargram (iOS)

Practical recipes and the gotchas that cost time, so they only cost it once.

## Two build configurations — don't confuse them

1. **Dev-signed** (default for device). `--xcodeManagedCodesigning` +
   `template_minimal_development_configuration.json` (gitignored — holds bundle id
   `org.<hex>.Telegram`, team id, api id/hash). Free Apple Developer → profile lives 7
   days, must be re-issued. Extensions disabled via `.bazelrc`
   (`--//Telegram:disableExtensions=True`) — otherwise free-account hits the App ID limit.

2. **Ad-hoc distribution cert** (long-lived IPA, ~1 year). For a device without
   jailbreak/TrollStore. Needs `.p12` + `.mobileprovision` and the device UDID registered
   on the issuing account. Stage them into a dir with `profiles/` + `certs/` and pass it
   as `--codesigningInformationPath` instead of `--xcodeManagedCodesigning`. Obtaining
   such a certificate is out of scope for this repo.

The CI variant (`appstore-configuration.json` + `fake-codesigning`) produces a
**fake-signed** IPA (`TeamIdentifier=not set`) — does NOT install on a normal device,
TrollStore only (unavailable on iOS 26+). Don't use it to install on an iPhone.

## Black screen on launch = signing problem, not code

`AppDelegate.swift` bails with "Error 2" if
`containerURL(forSecurityApplicationGroupIdentifier: "group.<bundleId>")` returns nil —
i.e. the app-group entitlement wasn't granted by the profile. **Check signing/app-group
first, then code.**

## First build on a fresh machine — three blockers

All three bite once, in this order.

1. **git submodules are not initialized.** `pnpm setup` clones without `--recurse-submodules`,
   so bazel fails with `No MODULE.bazel ... in build-system/bazel-rules/rules_swift`. Also
   `rlottie` and `tgcalls` use relative URLs (`../rlottie.git`) which resolve against a
   remote named `origin` — setup only creates `upstream`, so they fail to clone:

   ```sh
   git -C worktree remote add origin https://github.com/TelegramMessenger/Telegram-iOS.git
   git -C worktree submodule sync --recursive
   git -C worktree submodule update --init --recursive   # NOT --depth 1: pinned commits aren't tips
   ```

2. **`--disableExtensions` is not a `build` flag.** It exists only on `generateProject`.
   For `build`, add `build --//Telegram:disableExtensions=True` to the worktree's
   `.bazelrc` yourself — it is machine-specific, so no patch in the stack sets it.

3. **dav1d hardcodes `/Applications/Xcode.app` for device builds.**
   `third-party/dav1d/build-dav1d-bazel.sh` substitutes `xcode-select -p` only for the
   simulator and macOS crossfiles; the `arm64` path uses the upstream crossfile as-is, so
   with a versioned Xcode (`Xcode-26.4.0.app`) the build fails with `'stdlib.h' file not
   found`. Symlink it:

   ```sh
   ln -s /Applications/Xcode-26.4.0.app /Applications/Xcode.app
   ```

After that the first build is ~10 min cold (~2300 actions); everything after is incremental
(a one-line change is ~20 actions). Only a configuration switch (sim ↔ device, debug ↔ opt),
`pnpm rebase`, or deleting the output base / disk cache forces a cold rebuild again.
`pnpm export` does not touch the worktree or the cache.

## `./build.sh` — the fast path

Once the config below exists, `build.sh` wraps everything on this page: it syncs fork
sources, flips the local-only stgit patches a device build needs, runs `Make.py`, and
optionally strips the signature or installs the result.

```sh
./build.sh -r -s       # release, signed with your Apple ID -> Telegram.ipa
./build.sh -r -s -i    # same, then install on the device
./build.sh -r          # release, signature stripped -> Telegram-unsigned.ipa (for other people)
./build.sh -d -s -c    # debug, signed, wipe bazel state first
./build.sh -i          # install the newest .ipa already built, no rebuild
./build.sh -r -s --adhoc   # sign with a distribution certificate instead
```

**Signing defaults to your own Apple ID** (`--self`, i.e. `--xcodeManagedCodesigning`):
free, nothing to obtain, and the profile grants `group.<bundleId>` — the exact app group
Telegram derives at runtime, so nothing has to be patched. The catch is that a free profile
expires after 7 days; when it lapses the build fails on `Finding provisioning profile ...
failed` and opening `Telegram/Telegram.xcodeproj` in Xcode reissues it. `--adhoc` switches
to a distribution certificate from `CLEARGRAM_SIGNING_SRC` — longer-lived, but you have to
have one, and it usually grants a different app group (see below).

Personal values go in `build.local` (untracked, `cp build.local.example build.local`):

| variable | meaning |
| --- | --- |
| `CLEARGRAM_SIGN_METHOD` | `self` (default) or `adhoc` |
| `CLEARGRAM_SIGNING_SRC` | dir holding your `.mobileprovision` + `.p12` for `adhoc`, staged into `profiles/`+`certs/` on every run |
| `CLEARGRAM_DEVICE` | device UDID for `-i` (`xcrun devicectl list devices`) |
| `CLEARGRAM_XCODE` | Developer dir; defaults to `xcode-select -p` |
| `CLEARGRAM_CACHE_DIR` | bazel disk cache; defaults to `~/telegram-bazel-cache` |
| `CLEARGRAM_PNPM` | how to invoke pnpm, if not on PATH |
| `CLEARGRAM_*_PATCH` | names of your local stgit patches, if they differ from the defaults |

**Unsigned mode is what you hand to other people.** `Make.py` cannot skip codesigning, so
the build is signed and then stripped: `embedded.mobileprovision` (which carries the team
id, the certificate and every provisioned device UDID) and `_CodeSignature` are removed,
and the script fails if either survives in the archive. The recipient re-signs it.

**Local patches are flipped, not required.** Three optional `local__*` patches are pushed
and popped around the build and restored on exit; each is skipped when it is not in the
stack, so a fresh clone just builds:

| patch | why |
| --- | --- |
| `local__signing` | pins the app group your profile actually grants — applied only for `--adhoc` signed builds, popped for self-signed and unsigned ones |
| `local__disable-extensions` | a limited profile covers only the main app id; with extensions on, bazel demands a profile per extension target |
| `local__unsigned-dist` | skips entitlements validation, only for the build that gets stripped |

They are never exported: `pnpm export` writes applied patches only, and `scripts/ci/pre-commit.ts`
skips `local__*` on both sides, so they cannot reach `patches/` or the remote.

## Quick start (simulator, no signing)

Get api id/hash at https://core.telegram.org/api/obtaining_api_id (free, needs a Telegram
account). Get your Apple team id: Keychain Access → Certificates →
`Apple Development: your@email (XXXXXXXXXX)` → Details → Organizational Unit (the OU is the
team id). For a free Apple Developer account the team id is on
https://developer.apple.com/account → Membership Details.

1. Copy the build config and fill in your values:

   ```sh
   cp build-system/template_minimal_development_configuration.json.example \
      worktree/build-system/template_minimal_development_configuration.json
   # edit: bundle_id is preset; fill api_id, api_hash, team_id
   ```

   The `.example` is tracked here at the repo root; the filled-in copy belongs in
   `worktree/`, where `Make.py` runs. Mark it `skip-worktree` right away — see
   "App group and the build config" below.

2. Generate the Xcode project (one-time per `upstream-commit` bump):

   ```sh
   python3 build-system/Make/Make.py --overrideXcodeVersion \
     --cacheDir ~/telegram-bazel-cache \
     generateProject \
     --configurationPath build-system/template_minimal_development_configuration.json \
     --xcodeManagedCodesigning
   ```

3. Build for simulator (no signing needed):

   ```sh
   python3 build-system/Make/Make.py --overrideXcodeVersion \
     --cacheDir ~/telegram-bazel-cache \
     build \
     --configurationPath build-system/template_minimal_development_configuration.json \
     --xcodeManagedCodesigning --buildNumber=1 --configuration=debug_sim_arm64
   ```

   First build is long (~30–60 min, Bazel cold). `--continueOnError` after `build` to see
   all errors in one pass.

`Telegram/BUILD` is already parameterized via `telegram_bundle_id` (read from the config) —
**no branding patch is needed**, just fill the config. App group is derived as
`group.{telegram_bundle_id}`.

## Dev-signed build (device)

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/template_minimal_development_configuration.json \
  --xcodeManagedCodesigning --disableExtensions --buildNumber=1 --configuration=debug_arm64
```

Release variant: `--configuration=release_arm64`.

Install to device (UDID from `xcrun devicectl list devices`):

```sh
xcrun devicectl device install app --device <UDID> bazel-bin/Telegram/Telegram.ipa
```

Add `--continueOnError` after `build` (forwards to bazel's `--keep_going`) when verifying
edits that may break many files at once.

## Provisioning gotcha

`--xcodeManagedCodesigning` reads the profile from
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Bazel doesn't issue profiles
itself — Xcode does. Free profiles expire in 7 days; if the bundle id profile is missing or
expired, the build dies on `Finding provisioning profile //Telegram:Telegram_local_profile
failed`. Fix by opening `Telegram/Telegram.xcodeproj` (the rules_xcodeproj-generated one)
in Xcode and letting it regenerate.

The profile **must** carry the `group.<bundleId>` app-group entitlement — verify with
`security cms -D -i <profile> | plutil -extract Entitlements xml1 -o - -`.

## App group and the build config

Telegram derives its app group as `group.<bundleId>` at runtime, and the same string must
be granted by the profile — in the entitlement (`Telegram/BUILD`, `app_groups_fragment`)
and at runtime (`AppDelegate.swift`). If the signing profile registers a different group,
`containerURL(...)` returns nil and the app opens to a black screen. Either use a profile
that carries `group.<bundleId>`, or patch both places to the group the profile does grant.
Verify what a profile actually grants with:

```sh
security cms -D -i <profile> | plutil -extract Entitlements xml1 -o - -
```

and what ended up in the signed app with:

```sh
codesign -d --entitlements - Payload/Telegram.app | grep group
```

**The build configuration file is NOT in the stack.**
`build-system/template_minimal_development_configuration.json` holds api id/hash —
personal credentials tied to a my.telegram.org account. Keep it as a local file only:

```sh
git -C worktree update-index --skip-worktree build-system/template_minimal_development_configuration.json
# verify: `git ls-files -v <path>` prints "S"
```

Without this, `stg refresh` picks the file up and `pnpm export` bakes the credentials into
a patch. The root `.gitignore` does not help: the file lives in `worktree/`, a separate
clone. Upstream Telegram-iOS and Swiftgram both ship this file with placeholders only.

The `skip-worktree` bit lives in `worktree/.git` — `pnpm setup --force` recreates the
worktree and loses it. Re-apply after a fresh setup.

## Disk cache

`.bazelrc`/`xcodeproj.bazelrc` pin `--disk_cache=~/telegram-bazel-cache`,
`--experimental_disk_cache_gc_max_size=20G`, `--experimental_disk_cache_gc_max_age=30d`.
Bazel auto-evicts. Don't `rm -rf` the cache or the active output base — that throws away
warm state and forces a cold rebuild.

## Xcode version

`versions.json` pins Xcode 26.2, but build commands pass `--overrideXcodeVersion`. The
Xcode you use must have the matching **iOS platform/simulator runtime** installed —
otherwise `ibtool`/XibCompile fails with `iOS <ver> Platform Not Installed`. Switch:

```sh
sudo xcode-select -s /Applications/Xcode-26.4.0.app
# or for a single run:
DEVELOPER_DIR=/Applications/Xcode-26.4.0.app/Contents/Developer
```

## Keychain-search-list corruption

The fake-codesigning import (`ImportCertificates.py --path build-system/fake-codesigning/certs`)
injects `temp.keychain` into the search list and drops `login.keychain` →
`security find-identity -v -p codesigning` reports `0 valid identities`. Fix:
`security list-keychains -d user -s ~/Library/Keychains/login.keychain-db`.
**Never run the fake-codesigning import on this machine** unless you're building the CI
variant.

## Crash logs (from device)

```sh
# List Telegram crashes
xcrun devicectl device info files --domain-type systemCrashLogs --device <UDID> | grep Telegram

# Download a crash
xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs \
  --source "Telegram-YYYY-MM-DD-HHMMSS.ips" --destination /tmp/crash.ips

# Parse (IPS = two-line JSON)
python3 -c "
import json, re
data = open('/tmp/crash.ips').read()
j = json.loads(re.split(r'\n(?=\{)', data.strip())[1])
ct = next((t for t in j['threads'] if t.get('triggered')), j['threads'][0])
print(j.get('exception', {}))
for f in ct.get('frames', [])[:30]: print(' ', f.get('symbol',''), '+'+str(f.get('symbolLocation','')))
"
```

## Refreshing the simulator after a rebuild

`simctl install` does NOT replace an already-installed app when the build number is
unchanged (installd caches hard-links). Preferred: copy the whole freshly-built `.app`
over the installed bundle in place:

```sh
SIM="<simulator UDID>"
BUNDLE="<bundleId>"
SRC="$(find -L bazel-out -maxdepth 14 -path '*/Telegram_archive-root/Payload/Telegram.app' -type d | head -1)"
DEST="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" app)"
[ -x "$SRC/Telegram" ] || { echo "no fresh bundle at SRC=$SRC — aborting"; exit 1; }
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null
rm -rf "$DEST" && cp -Rp "$SRC" "$DEST"
xcrun simctl launch "$SIM" "$BUNDLE"
```

The data container lives separately (keyed by bundle id) — login/account is preserved.

## Tests

`Make.py test --target <label>` (default `Tests/AllTests` — has a dangling `TgCallsTests`,
don't use the default). First app-side `ios_unit_test` is
`//submodules/TextFormat:TextFormatTests`.
