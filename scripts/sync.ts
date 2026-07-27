import { worktreeDir } from './config.js'
import { linkForkSource, success } from './lib.js'

// Re-copy fork source files (src/swift/ClearGram/<area>/) into the worktree. Run this after
// editing fork Swift code so Bazel sees the updated files without a full `pnpm setup`.
const dirty = await linkForkSource(worktreeDir)
success(dirty ? 'Synced fork sources' : 'Fork sources up to date')
