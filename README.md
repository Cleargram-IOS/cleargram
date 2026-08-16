# Cleargram

An unofficial Telegram iOS client: upstream Telegram-iOS plus a stack of patches that remove
stock clutter and add quality-of-life features. Every behaviour change is off by default and
lives behind a toggle in **Settings ▸ Cleargram**.

Cleargram is a **patchset**, not a classical fork. `worktree/` is a clone of
[TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) pinned to
the commit in `upstream-commit`, on top of which [stgit](https://stacked-git.github.io)
applies `patches/` in the order given by `series`. Nothing of upstream is vendored here, so
the whole delta against official Telegram is a directory you can read in one sitting, and
moving to a newer upstream is a rebase rather than a merge.

Full feature list: [`docs/features.md`](docs/features.md).

## Requirements

macOS, Xcode 26+, `git`, `stg` (`brew install stgit`), Node 20+, `pnpm`, and a Telegram
api id/hash from [my.telegram.org](https://my.telegram.org/apps) (free).

## Setup

```sh
pnpm install
pnpm setup    # clone upstream into worktree/, init stgit, apply series, sync fork sources
```

Then fill in the build config — it holds your api id/hash and is never committed:

```sh
cp build-system/template_minimal_development_configuration.json.example \
   worktree/build-system/template_minimal_development_configuration.json
git -C worktree update-index --skip-worktree \
   build-system/template_minimal_development_configuration.json
```

## Build

```sh
cp build.local.example build.local   # signing dir, device UDID, Xcode
./build.sh -r -s -i                  # release, signed, install on the device
./build.sh -r                        # release, signature stripped — the one to hand out
```

First build is 30–60 min cold; incremental builds are seconds to minutes. Signing options,
the app-group gotcha (a black screen at launch is almost always signing, not code) and
crash-log retrieval are in [`docs/build-codesigning.md`](docs/build-codesigning.md).

## Repo layout

| path | what |
| --- | --- |
| `upstream-commit` | pinned Telegram-iOS commit |
| `patches/`, `series` | stgit export + apply order — **generated, never hand-edit** |
| `src/swift/ClearGram/` | fork Swift code, copied into the worktree by `pnpm sync` |
| `scripts/` | `setup` / `sync` / `export` / `rebase` / `find-patches` (TypeScript via tsx) |
| `worktree/` | local clone of upstream with the stack applied (gitignored) |
| `docs/` | build guide, feature list, workflow notes |

Stock patches stay small on purpose — a guard, a hook, a call site. Real logic goes into a
fork file under `src/swift/ClearGram/<Submodule>/`, which `pnpm sync` copies into the
worktree (Bazel does not follow symlinks out of its workspace). A new fork directory has to
be registered in `forkSyncDirs` in `scripts/config.ts`, or it is never copied.

## Working on a patch

```sh
stg -C worktree new feature__my-patch -m "Add my feature"
# ...edit worktree/...
stg -C worktree refresh
pnpm export        # rewrites patches/ + series
```

To change an existing patch, float it to the top first
(`stg -C worktree float <name>`), edit, `refresh`, `export`. `pnpm find-patches <path>`
shows which patches touch a file; `pnpm rebase <commit|latest>` moves the stack to a newer
upstream. A pre-commit hook checks that `patches/` matches the stack.

Patch groups: `bugfix` (upstream bug), `feature` (new capability), `debloat` (only hides
stock behaviour), `hooks` (wiring for fork code), `misc` (build, branding, infra).
Conventions, architecture notes and the compliance rules are in [`AGENTS.md`](AGENTS.md).

## Scope

Patches that would break the Telegram API Terms of Service are out — most concretely,
nothing here touches sponsored messages or promoted chats, and nothing fakes presence, read
receipts or typing status to the server. Hiding stock UI locally is fair game; lying to the
service is not.

## AI assistance disclosure

Parts of this fork were written with AI assistance. Everything was reviewed by the
maintainer before being committed, who takes full responsibility for its contents.

## License

Patches and fork code: MIT. Upstream Telegram-iOS remains under its own license (GPLv2).
Telegram's name, logo and branding are not covered by that license and are not used here.
