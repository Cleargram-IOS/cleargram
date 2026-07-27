import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const upstreamUrl = 'https://github.com/TelegramMessenger/Telegram-iOS.git'
export const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), '..')
export const worktreeDir = join(rootDir, 'worktree')
export const patchesDir = join(rootDir, 'patches')
export const seriesFile = join(rootDir, 'series')
export const upstreamCommitFile = join(rootDir, 'upstream-commit')

export const workBranch = 'cleargram'

// Bundle id, app group, team id — see build-system/template_minimal_development_configuration.json.example
// (the real config is gitignored — it holds api id/hash/team id).
export const bundleId = 'org.YOUR_BUNDLE_ID_HERE.Telegram'
export const appGroup = `group.${bundleId}`

// Shared-data key range for fork settings. 30..39 is far from stock (<=22) and keetgram (23,24).
export const clearSharedDataKeyRange = {
  clearConfig: 30, // ClearConfigSettings (toggles)
  hiddenChats: 31, // HiddenChatsSettings (per-peer hidden)
  hiddenMessages: 32, // HiddenMessagesSettings (per-message hidden)
  reserved: 33, // reserved
} as const

// Fork source layout: each subdirectory under src/swift/ClearGram/<SubmoduleName>/ is
// symlinked into submodules/<SubmoduleName>/Sources/ClearGram/ in the worktree. The new
// files still need to be registered in the submodule's BUILD.bazel — that's what the
// misc__build-config / per-feature patch does. This map only wires the physical symlinks;
// BUILD registration is a separate concern.
//
// Keetgram puts fork settings types into TelegramUIPreferences (same module as the shared-data
// keys) and fork management UI into DebugSettingsUI — we follow the same placement so that
// every consumer already depends on the right module.
export interface ForkSyncDir {
  source: string
  target: string
}

export const forkSyncDirs: ForkSyncDir[] = [
  {
    source: 'src/swift/ClearGram/TelegramUIPreferences',
    target: 'submodules/TelegramUIPreferences/Sources/ClearGram',
  },
  {
    source: 'src/swift/ClearGram/DebugSettingsUI',
    target: 'submodules/DebugSettingsUI/Sources/ClearGram',
  },
  {
    source: 'src/swift/ClearGram/TextFormat',
    target: 'submodules/TextFormat/Sources/ClearGram',
  },
]

// Kept for backward compat with any external callers; prefer forkSyncDirs.
export interface ForkSyncFile {
  source: string
  target: string
  directory?: boolean
}

export const forkSyncFiles: ForkSyncFile[] = forkSyncDirs.map(d => ({
  source: d.source,
  target: d.target,
  directory: true,
}))
