#!/bin/bash
# Build helper around Make.py.
#
#   ./build.sh -r          release, unsigned  -> Telegram-unsigned.ipa (hand to other people)
#   ./build.sh -r -s       release, signed    -> Telegram.ipa
#   ./build.sh -r -s -i    same, then install on the device
#   ./build.sh -d -s -c    debug, signed, clean bazel state first
#   ./build.sh -i          install the newest existing .ipa, no rebuild
#
# Configuration lives in `build.local` (untracked, sourced below if present) or in the
# environment. See docs/build-codesigning.md.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Personal, machine-specific values: signing material, device, Xcode, local patch names.
# Keep them out of the repository — `build.local` is untracked.
[ -f "$REPO/build.local" ] && . "$REPO/build.local"

# How to sign: `self` uses your own Apple ID through Xcode (free, profile expires after 7
# days), `adhoc` uses a distribution certificate you supply. Overridden by --self / --adhoc.
SIGN_METHOD="${CLEARGRAM_SIGN_METHOD:-self}"
# Directory holding your `.mobileprovision` and `.p12`. Only used by `adhoc`.
SIGNING_SRC="${CLEARGRAM_SIGNING_SRC:-$HOME/.cleargram/signing}"
# Where they get staged for Make.py, which wants `profiles/` + `certs/` side by side.
SIGNING_DIR="${CLEARGRAM_SIGNING_DIR:-/tmp/tg-cs}"
# Device UDID for `-i`. Find yours with `xcrun devicectl list devices`.
DEVICE="${CLEARGRAM_DEVICE:-}"
# Xcode to build with. Defaults to the one `xcode-select` points at.
XCODE="${CLEARGRAM_XCODE:-$(xcode-select -p)}"
# Bazel disk cache, shared across configurations.
CACHE_DIR="${CLEARGRAM_CACHE_DIR:-$HOME/telegram-bazel-cache}"
# How to invoke pnpm (e.g. `npx --yes pnpm@10.33.2` when it is not installed globally).
PNPM="${CLEARGRAM_PNPM:-pnpm}"

# Optional local stgit patches, flipped around the build (see below). Each one is skipped
# when it is not in the stack, so a checkout without them just builds.
PATCH_SIGNING="${CLEARGRAM_SIGNING_PATCH:-local__signing}"
PATCH_NO_EXTENSIONS="${CLEARGRAM_NO_EXTENSIONS_PATCH:-local__disable-extensions}"
PATCH_UNSIGNED_DIST="${CLEARGRAM_UNSIGNED_DIST_PATCH:-local__unsigned-dist}"

usage() {
    cat >&2 <<'EOF'
usage: ./build.sh (-r | -d) [-s] [-c] [-i] [-f]

  -r, --release   optimised build
  -d, --debug     faster build, unoptimised
  -s, --sign      keep the signature (otherwise it is stripped from the .ipa,
                  for handing to other people)
      --self      sign with your own Apple ID via Xcode (default) — free, but
                  the provisioning profile expires after 7 days
      --adhoc     sign with a distribution certificate from CLEARGRAM_SIGNING_SRC
  -c, --clear     wipe local bazel state first
  -i, --install   install on the device afterwards
  -f, --file      also copy the .ipa to ~/Downloads

The .ipa always lands in worktree/build/artifacts-<config>/; -f puts a copy in
~/Downloads under a friendlier name.

Used alone, -i installs the most recent .ipa without rebuilding anything; it
looks in ~/Downloads and in worktree/build/artifacts-*/.

Without --sign a device .ipa is still produced, with the signature, the
provisioning profile and the device UDIDs stripped out — that is the one to
hand to other people, who re-sign it themselves.

--clear keeps the shared disk cache, so it costs analysis time rather than a
full recompile.

Configuration (build.local or environment):
  CLEARGRAM_SIGN_METHOD   self (default) | adhoc
  CLEARGRAM_SIGNING_SRC   dir with .mobileprovision + .p12, for adhoc
  CLEARGRAM_DEVICE        device UDID for --install
  CLEARGRAM_XCODE         Developer dir to build with
  CLEARGRAM_CACHE_DIR     bazel disk cache
EOF
    exit 2
}

FLAVOUR=""
SIGN=0
CLEAN=0
INSTALL=0
COPY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -r|--release) FLAVOUR=release ;;
        -d|--debug)   FLAVOUR=debug ;;
        -s|--sign)    SIGN=1 ;;
        --self)       SIGN_METHOD=self ;;
        --adhoc)      SIGN_METHOD=adhoc ;;
        -c|--clear)   CLEAN=1 ;;
        -i|--install) INSTALL=1 ;;
        -f|--file)    COPY=1 ;;
        -h|--help)    usage ;;
        *) echo "error: unknown option '$1'" >&2; usage ;;
    esac
    shift
done

require_device() {
    [ -n "$DEVICE" ] || {
        echo "error: no device set — put CLEARGRAM_DEVICE in build.local" >&2
        echo "       (find the UDID with: xcrun devicectl list devices)" >&2
        exit 1
    }
}

# Is a patch present in the stack at all? Absent ones are simply not flipped.
patch_exists() {
    printf '%s\n' "$SERIES" | grep -qF -- "$1"
}

# `-i` on its own means "install whatever was built last" — no rebuild.
if [ -z "$FLAVOUR" ]; then
    if [ "$INSTALL" = 1 ] && [ "$CLEAN" = 0 ] && [ "$SIGN" = 0 ]; then
        require_device
        LATEST=""
        for candidate in "$HOME/Downloads"/Cleargram-*.ipa \
                         "$REPO/worktree/build"/artifacts-*/Telegram*.ipa; do
            [ -f "$candidate" ] || continue
            if [ -z "$LATEST" ] || [ "$candidate" -nt "$LATEST" ]; then
                LATEST="$candidate"
            fi
        done
        [ -n "$LATEST" ] || { echo "error: no .ipa found — build one first" >&2; exit 1; }
        echo "==> installing $LATEST"
        echo "    built $(date -r "$LATEST" '+%Y-%m-%d %H:%M')"
        xcrun devicectl device install app --device "$DEVICE" "$LATEST"
        exit 0
    fi
    echo "error: pick --release or --debug" >&2
    usage
fi

# Installing a simulator build on a phone is not a thing.
[ "$INSTALL" = 1 ] && SIGN=1
[ "$INSTALL" = 1 ] && require_device

# Both modes build for the device: an unsigned build is meant for redistribution, so it has
# to be a real device .ipa. Make.py cannot skip codesigning, so it is stripped afterwards.
CONFIG="${FLAVOUR}_arm64"

# Make.py always demands a codesigning source, even for the build we strip afterwards — the
# two modes are mutually exclusive arguments, so pick one either way.
case "$SIGN_METHOD" in
    self)
        # Xcode issues the profile, not bazel. A free Apple Developer profile lives 7 days;
        # when it has lapsed the build dies on "Finding provisioning profile ... failed" and
        # opening Telegram/Telegram.xcodeproj in Xcode reissues it.
        echo "==> signing with your Apple ID (Xcode-managed profile)"
        CODESIGN_ARGS=(--xcodeManagedCodesigning)
        ;;
    adhoc)
        # Always re-stage: /tmp is wiped by a reboot, and a stale copy would silently sign
        # with the previous certificate after the source ones are swapped.
        echo "==> staging codesigning material from $SIGNING_SRC"
        [ -d "$SIGNING_SRC" ] || {
            echo "error: $SIGNING_SRC not found — set CLEARGRAM_SIGNING_SRC in build.local" >&2
            echo "       (or drop --adhoc to sign with your own Apple ID)" >&2
            exit 1
        }
        rm -rf "$SIGNING_DIR"
        mkdir -p "$SIGNING_DIR/profiles" "$SIGNING_DIR/certs"
        cp "$SIGNING_SRC"/*.mobileprovision "$SIGNING_DIR/profiles/"
        cp "$SIGNING_SRC"/*.p12 "$SIGNING_DIR/certs/"
        CODESIGN_ARGS=(--codesigningInformationPath "$SIGNING_DIR")
        ;;
    *)
        echo "error: unknown signing method '$SIGN_METHOD' — use self or adhoc" >&2
        exit 1
        ;;
esac

# The signing patch hardcodes the app group that your profile actually grants. Telegram
# derives `group.<bundleId>` at runtime, which is exactly what an Xcode-managed profile
# registers — so it is only needed for a distribution certificate that grants some other
# group string.
#   adhoc + signed -> it must be applied, or the app cannot reach its container (black screen)
#   self / unsigned -> it must NOT be applied, or whoever installs the .ipa under a profile
#                      granting `group.<bundleId>` gets that same black screen
# The script flips it as needed and puts the stack back the way it found it on exit, so
# neither mode leaves the other one broken.
# The disable-extensions patch belongs in every device build off a limited profile: it covers
# only the main app id, so with extensions enabled bazel demands a .mobileprovision per
# extension target and the build dies during analysis.
# Capture first: `stg ... | grep -q` makes grep close the pipe on the first match, stg dies
# with SIGPIPE and `set -o pipefail` turns a successful match into a failed pipeline.
SERIES="$(stg -C "$REPO/worktree" series 2>/dev/null || true)"
APPLIED="$(stg -C "$REPO/worktree" series --applied 2>/dev/null || true)"

if patch_exists "$PATCH_NO_EXTENSIONS" && \
   ! printf '%s\n' "$APPLIED" | grep -qF -- "$PATCH_NO_EXTENSIONS"; then
    echo "==> applying $PATCH_NO_EXTENSIONS"
    stg -C "$REPO/worktree" push "$PATCH_NO_EXTENSIONS" || {
        echo "error: could not apply $PATCH_NO_EXTENSIONS" >&2; exit 1; }
fi

SIGNING_WAS_APPLIED=0
printf '%s\n' "$APPLIED" | grep -qF -- "$PATCH_SIGNING" && SIGNING_WAS_APPLIED=1 || true
SIGNING_FLIPPED=0
DIST_FLIPPED=0
STAGE=""

cleanup() {
    [ -n "$STAGE" ] && rm -rf "$STAGE"
    if [ "$DIST_FLIPPED" = 1 ]; then
        if [ "$DIST_WAS_APPLIED" = 1 ]; then
            stg -C "$REPO/worktree" push "$PATCH_UNSIGNED_DIST" >/dev/null 2>&1 || true
        else
            stg -C "$REPO/worktree" pop "$PATCH_UNSIGNED_DIST" >/dev/null 2>&1 || true
        fi
    fi
    if [ "$SIGNING_FLIPPED" = 1 ]; then
        echo "==> restoring $PATCH_SIGNING"
        if [ "$SIGNING_WAS_APPLIED" = 1 ]; then
            stg -C "$REPO/worktree" push "$PATCH_SIGNING" >/dev/null || \
                echo "warning: could not re-apply $PATCH_SIGNING — do it by hand" >&2
        else
            stg -C "$REPO/worktree" pop "$PATCH_SIGNING" >/dev/null || \
                echo "warning: could not pop $PATCH_SIGNING — do it by hand" >&2
        fi
    fi
}
trap cleanup EXIT

# The unsigned-dist patch skips entitlements validation, which only makes sense for the build
# we strip and hand out. It must be off for a signed build so real mistakes still fail loudly.
DIST_WAS_APPLIED=0
printf '%s\n' "$APPLIED" | grep -qF -- "$PATCH_UNSIGNED_DIST" && DIST_WAS_APPLIED=1 || true

NEED_SIGNING_PATCH=0
[ "$SIGN" = 1 ] && [ "$SIGN_METHOD" = adhoc ] && NEED_SIGNING_PATCH=1

if patch_exists "$PATCH_SIGNING"; then
    if [ "$NEED_SIGNING_PATCH" = 1 ] && [ "$SIGNING_WAS_APPLIED" = 0 ]; then
        echo "==> applying $PATCH_SIGNING (ad-hoc signing needs the app group)"
        stg -C "$REPO/worktree" push "$PATCH_SIGNING" || {
            echo "error: could not apply $PATCH_SIGNING" >&2; exit 1; }
        SIGNING_FLIPPED=1
    elif [ "$NEED_SIGNING_PATCH" = 0 ] && [ "$SIGNING_WAS_APPLIED" = 1 ]; then
        echo "==> popping $PATCH_SIGNING (this build must not hardcode the app group)"
        stg -C "$REPO/worktree" pop "$PATCH_SIGNING" || {
            echo "error: could not pop $PATCH_SIGNING — is the worktree dirty?" >&2; exit 1; }
        SIGNING_FLIPPED=1
    fi
fi

if patch_exists "$PATCH_UNSIGNED_DIST"; then
    if [ "$SIGN" = 0 ] && [ "$DIST_WAS_APPLIED" = 0 ]; then
        echo "==> applying $PATCH_UNSIGNED_DIST"
        stg -C "$REPO/worktree" push "$PATCH_UNSIGNED_DIST" || {
            echo "error: could not apply $PATCH_UNSIGNED_DIST" >&2; exit 1; }
        DIST_FLIPPED=1
    elif [ "$SIGN" = 1 ] && [ "$DIST_WAS_APPLIED" = 1 ]; then
        echo "==> popping $PATCH_UNSIGNED_DIST"
        stg -C "$REPO/worktree" pop "$PATCH_UNSIGNED_DIST" || {
            echo "error: could not pop $PATCH_UNSIGNED_DIST" >&2; exit 1; }
        DIST_FLIPPED=1
    fi
fi

ARTIFACTS="$REPO/worktree/build/artifacts-$CONFIG"

echo "==> syncing fork sources"
(cd "$REPO" && $PNPM run sync)

cd "$REPO/worktree"

if [ "$CLEAN" = 1 ]; then
    echo "==> cleaning bazel state"
    DEVELOPER_DIR="$XCODE" python3 build-system/Make/Make.py \
        --overrideXcodeVersion --cacheDir "$CACHE_DIR" clean
fi

echo "==> building $CONFIG$([ "$SIGN" = 1 ] && echo ' (signed)' || echo ' (unsigned)')"
DEVELOPER_DIR="$XCODE" python3 build-system/Make/Make.py \
    --overrideXcodeVersion \
    --cacheDir "$CACHE_DIR" \
    build \
    --continueOnError \
    --configurationPath build-system/template_minimal_development_configuration.json \
    "${CODESIGN_ARGS[@]}" \
    --configuration="$CONFIG" \
    --buildNumber=1 \
    --outputBuildArtifactsPath="$ARTIFACTS"

echo
[ -f "$ARTIFACTS/Telegram.ipa" ] || { echo "error: no .ipa at $ARTIFACTS" >&2; exit 1; }

if [ "$SIGN" = 1 ]; then
    OUT="$ARTIFACTS/Telegram.ipa"
else
    # Strip everything identifying: embedded.mobileprovision carries the team id, the signing
    # certificate and the provisioned device UDIDs. Whoever installs this re-signs it anyway.
    OUT="$ARTIFACTS/Telegram-unsigned.ipa"
    STAGE="$(mktemp -d)"
    echo "==> stripping signature"
    unzip -q "$ARTIFACTS/Telegram.ipa" -d "$STAGE"
    rm -f "$STAGE/Payload/Telegram.app/embedded.mobileprovision"
    find "$STAGE/Payload" -name _CodeSignature -type d -prune -exec rm -rf {} +
    rm -f "$OUT"
    (cd "$STAGE" && zip -qry "$OUT" Payload)
    remaining=$(unzip -l "$OUT" | grep -cE "mobileprovision|_CodeSignature" || true)
    [ "$remaining" = 0 ] || { echo "error: $remaining signing artefact(s) still in the .ipa" >&2; exit 1; }
fi

echo "==> $OUT"
ls -lh "$OUT"

if [ "$COPY" = 1 ]; then
    if [ "$SIGN" = 1 ]; then
        DEST="$HOME/Downloads/Cleargram-$FLAVOUR.ipa"
    else
        DEST="$HOME/Downloads/Cleargram-$FLAVOUR-unsigned.ipa"
    fi
    cp "$OUT" "$DEST"
    echo "==> $DEST"
fi

if [ "$INSTALL" = 1 ]; then
    echo
    echo "==> installing on $DEVICE"
    xcrun devicectl device install app --device "$DEVICE" "$OUT"
fi
