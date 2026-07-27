# Cleargram

A Telegram iOS patchset fork — minus the bullshit, plus the features.

Cleargram is a **patchset**, not a classical fork. `worktree/` is a clone of
`TelegramMessenger/Telegram-iOS` pinned to a specific commit, on top of which stgit applies
patches from `patches/`. Fork code and patches live in this repo separately from upstream —
easy to audit, easy to rebase.

## Quick start

Requirements: macOS, Xcode 26+, `git`, `stg` (`brew install stgit`), Node 20+, `pnpm`.

```sh
pnpm install
pnpm setup          # clone upstream into worktree/, init stgit, apply series
# next — generateProject + build, see docs/build-codesigning.md
```

## Repo layout

- `upstream-commit` — pinned Telegram-iOS commit
- `patches/` — stgit patch export (generated, don't hand-edit)
- `series` — apply order (generated)
- `src/swift/ClearGram/` — fork Swift code (copied into the worktree by `pnpm sync`)
- `worktree/` — local clone of upstream with stgit (gitignored)
- `scripts/` — `setup`/`sync`/`export`/`rebase`/`find-patches` (TypeScript via tsx)
- `docs/` — build/codesigning guide, feature list

## Patches

| group | when |
| --- | --- |
| `bugfix` | fixes an upstream bug |
| `feature` | adds user-facing capability |
| `debloat` | hides stock behavior behind a toggle |
| `hooks` | thin hooks for fork code, no visible effect on their own |
| `misc` | build, branding, infra |

Feature list — [`docs/features.md`](docs/features.md). Patchset workflow rules —
[`AGENTS.md`](AGENTS.md).

## AI assistance disclosure

Development of this fork was assisted by AI tools (Claude / opencode). All code produced
under AI assistance was reviewed by the maintainer before being committed. The maintainer
takes full responsibility for the contents of this repository.

## License

MIT (patches + fork code). Upstream — under its own license.
