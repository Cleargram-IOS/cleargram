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

// Shared-data key range for fork settings. 30..39 stays clear of stock, which occupies <=22.
export const clearSharedDataKeyRange = {
  clearConfig: 30, // ClearConfigSettings (toggles)
  hiddenChats: 31, // HiddenChatsSettings (per-peer hidden)
  hiddenMessages: 32, // HiddenMessagesSettings (per-message hidden)
  lastFm: 33, // ClearLastFmSettings (Last.fm credentials + scrobble queue)
} as const

// Fork source layout: each subdirectory under src/swift/ClearGram/<SubmoduleName>/ is
// symlinked into submodules/<SubmoduleName>/Sources/ClearGram/ in the worktree. The new
// files still need to be registered in the submodule's BUILD.bazel — that's what the
// misc__build-config / per-feature patch does. This map only wires the physical symlinks;
// BUILD registration is a separate concern.
//
// Fork settings types go into TelegramUIPreferences (same module as the shared-data keys) and
// fork management UI into DebugSettingsUI, so that every consumer already depends on the
// right module.
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
  {
    source: 'src/swift/ClearGram/ChatListUI',
    target: 'submodules/ChatListUI/Sources/ClearGram',
  },
  {
    source: 'src/swift/ClearGram/LegacyMediaPickerUI',
    target: 'submodules/LegacyMediaPickerUI/Sources/ClearGram',
  },
  {
    source: 'src/swift/ClearGram/MediaPickerUI',
    target: 'submodules/MediaPickerUI/Sources/ClearGram',
  },
  {
    source: 'src/swift/ClearGram/PeerInfoScreen',
    target: 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ClearGram',
  },
  // Fork code that needs the player types (AccountContext/UniversalMediaPlayer) has to live in a
  // module that already depends on them; TelegramUI is that module, and its BUILD globs
  // Sources/**, so nothing extra is registered.
  {
    source: 'src/swift/ClearGram/TelegramUI',
    target: 'submodules/TelegramUI/Sources/ClearGram',
  },
  // Shared by two chat-message node modules (voice and round video), so it lives in the module
  // that already owns on-device speech recognition rather than in either caller.
  {
    source: 'src/swift/ClearGram/LocalAudioTranscription',
    target: 'submodules/Media/LocalAudioTranscription/Sources/ClearGram',
  },
]

// Build stamp: `pnpm sync` copies the placeholder from src/ like any other fork source, then
// overwrites this path with the real upstream version/commit + cleargram commit (writeBuildInfo
// in lib.ts). Cleargram Settings shows that line at the bottom.
//
// It sits in DebugSettingsUI, next to the settings screen that reads it, rather than in
// TelegramUIPreferences: the file changes with every cleargram commit, and nearly every module
// depends on the preferences one, so that placement would invalidate the whole tree.
export const buildInfoTarget = 'submodules/DebugSettingsUI/Sources/ClearGram/ClearBuildInfo.swift'

// Where a dirty build's working-tree patch is archived, named after the `+<id>` suffix the app
// shows. Repo-relative and under the gitignored build/, so the archive can never feed back into
// the id it is named after.
export const dirtyStampsDir = 'build/dirty-stamps'

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
