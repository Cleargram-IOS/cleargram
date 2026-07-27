# Build & Codesigning — Cleargram (iOS)

Adapted from the fork-specific part of keetgram's `CLAUDE.md` to the patchset structure.
Practical recipes and the gotchas keetgram hit, so cleargram doesn't repeat them.

## Two build configurations — don't confuse them

1. **Dev-signed** (default for device). `--xcodeManagedCodesigning` +
   `template_minimal_development_configuration.json` (gitignored — holds bundle id
   `org.<hex>.Telegram`, team id, api id/hash). Free Apple Developer → profile lives 7
   days, must be re-issued. Extensions disabled via `.bazelrc`
   (`--//Telegram:disableExtensions=True`) — otherwise free-account hits the App ID limit.

2. **Ad-hoc / ad-hoc service cert** (long-lived IPA, ~1 year). For device without
   jailbreak/TrollStore. Needs `.p12` + `.mobileprovision` (ad-hoc distribution), device
   UDID registered. See "Ad-hoc IPA" below.

The CI variant (`appstore-configuration.json` + `fake-codesigning`) produces a
**fake-signed** IPA (`TeamIdentifier=not set`) — does NOT install on a normal device,
TrollStore only (unavailable on iOS 26+). Don't use it to install on an iPhone.

## Black screen on launch = signing problem, not code

`AppDelegate.swift` bails with "Error 2" if
`containerURL(forSecurityApplicationGroupIdentifier: "group.<bundleId>")` returns nil —
i.e. the app-group entitlement wasn't granted by the profile. **Check signing/app-group
first, then code.**

## Quick start (simulator, no signing)

Get api id/hash at https://core.telegram.org/api/obtaining_api_id (free, needs a Telegram
account). Get your Apple team id: Keychain Access → Certificates →
`Apple Development: your@email (XXXXXXXXXX)` → Details → Organizational Unit (the OU is the
team id). For a free Apple Developer account the team id is on
https://developer.apple.com/account → Membership Details.

1. Copy the build config and fill in your values:

   ```sh
   cp build-system/template_minimal_development_configuration.json.example \
      build-system/template_minimal_development_configuration.json
   # edit: bundle_id is preset; fill api_id, api_hash, team_id
   ```

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

## App-group patch — mandatory for ad-hoc

Telegram derives its app group as `group.<bundleId>` at runtime. The service certificate
registers unrelated group strings (never `group.<bundleId>`). Without patching the app
group in **both** places — the entitlement (`Telegram/BUILD`, `app_groups_fragment`) AND
runtime (`AppDelegate.swift`) — `containerURL(...)` returns nil → black screen.

Cleargram keeps these as `misc__branding` / `misc__build-config` in the stgit stack (on the
remote: normal commits, not skip-worktree — keetgram hid them skip-worktree because its
bundle id was a local device hack; for a patchset repo with a stable bundle id that's
unnecessary).

## Ad-hoc IPA — the working recipe

Needs an ad-hoc service cert: `.p12` + `.mobileprovision`, team like `<TEAM_ID>`, your
own bundle id, device UDID registered. The `.p12` password is NOT in the repo.

1. **Import the cert** (macOS `security` can't read modern OpenSSL-3 `.p12` — convert to
   legacy first):

   ```sh
   P=<signing dir>/*.p12
   openssl pkcs12 -in $P -passin pass:<pw> -nodes | \
     openssl pkcs12 -export -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
       -macalg sha1 -passout pass:<pw> -out /tmp/legacy.p12
   security import /tmp/legacy.p12 -k ~/Library/Keychains/login.keychain-db \
     -P <pw> -T /usr/bin/codesign
   ```

2. **Stage the codesigning dir** (`--codesigningInformationPath` wants `profiles/` +
   `certs/`):

   ```sh
   D=/tmp/tg-cs; rm -rf $D; mkdir -p $D/profiles $D/certs
   cp <signing dir>/*.mobileprovision $D/profiles/
   cp /tmp/legacy.p12 $D/certs/
   ```

3. **Build + sign** (NOT `--xcodeManagedCodesigning`):

   ```sh
   DEVELOPER_DIR=/Applications/Xcode-26.4.0.app/Contents/Developer \
   python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache \
     build \
     --configurationPath build-system/template_minimal_development_configuration.json \
     --codesigningInformationPath $D \
     --configuration=release_arm64 --buildNumber=1 \
     --outputBuildArtifactsPath="$PWD/build/artifacts-ad-hoc"
   ```

4. **Install:** `xcrun devicectl device install app --device <UDID> build/artifacts-ad-hoc/Telegram.ipa`
   (device unlocked). Ad-hoc distribution → runs with no "trust developer" step.

Verify the patched app group made it into the signed app:
`codesign -d --entitlements - Payload/Telegram.app | grep <group>`.

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
