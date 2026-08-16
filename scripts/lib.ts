import { createHash } from 'node:crypto'
import { existsSync } from 'node:fs'
import fs from 'node:fs/promises'
import { dirname, isAbsolute, join, relative, resolve } from 'node:path'
import { $, chalk } from 'zx'
import {
  buildInfoTarget,
  dirtyStampsDir,
  forkSyncDirs,
  rootDir,
  seriesFile,
  upstreamCommitFile,
  upstreamUrl,
  workBranch,
} from './config.js'

$.verbose = false

export function step(message: string) {
  console.log(`${chalk.blue('==>')} ${message}`)
}

export function success(message: string) {
  console.log(`${chalk.green('ok')} ${message}`)
}

export function warn(message: string) {
  console.log(`${chalk.yellow('warn')} ${message}`)
}

export function cd(cwd: string) {
  return $({ cwd })
}

export function resolveFromRoot(input: string | undefined, fallback?: string) {
  if (!input) {
    if (fallback) {
      return fallback
    }
    throw new Error('Missing required path argument')
  }
  return isAbsolute(input) ? input : resolve(rootDir, input)
}

export async function readPinnedUpstreamCommit() {
  const value = (await fs.readFile(upstreamCommitFile, 'utf8')).trim()
  if (!/^[0-9a-f]{7,40}$/i.test(value)) {
    throw new Error(`Set ${relative(rootDir, upstreamCommitFile)} to a real commit hash first`)
  }
  return value
}

export async function writePinnedUpstreamCommit(commit: string) {
  await fs.writeFile(upstreamCommitFile, `${commit}\n`)
}

export async function ensureEmptyCloneTarget(targetDir: string) {
  if (!existsSync(targetDir)) {
    return
  }
  const entries = await fs.readdir(targetDir)
  if (entries.length > 0 && !entries.includes('.git')) {
    throw new Error(`Target exists and is not empty: ${targetDir}`)
  }
}

export async function ensureDir(dir: string) {
  await fs.mkdir(dir, { recursive: true })
}

export async function cloneUpstream(targetDir: string, commit: string) {
  await ensureEmptyCloneTarget(targetDir)
  if (!existsSync(join(targetDir, '.git'))) {
    step(`Cloning upstream into ${targetDir}`)
    // Optional local reference: CLEAR_LOCAL_UPSTREAM=/path/to/Telegram-iOS to speed up
    // the clone by sharing object storage. Falls back to a plain network clone.
    const localRef = process.env.CLEAR_LOCAL_UPSTREAM
    if (localRef && existsSync(join(localRef, '.git'))) {
      step(`Using local reference ${localRef}`)
      await $`git clone --reference-if-able ${localRef} ${upstreamUrl} ${targetDir}`
    } else {
      await $`git clone ${upstreamUrl} ${targetDir}`
    }
  } else {
    step(`Reusing existing checkout in ${targetDir}`)
  }
  await ensureUpstreamRemote(targetDir)
  const git = cd(targetDir)
  step(`Checking out ${commit}`)
  await git`git checkout ${commit}`
}

export async function ensureUpstreamRemote(repoDir: string) {
  const git = cd(repoDir)
  const remotes = (await git`git remote`)
    .stdout
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)

  if (remotes.includes('upstream')) {
    return
  }

  if (remotes.includes('origin')) {
    step('Renaming origin remote to upstream')
    await git`git remote rename origin upstream`
    return
  }

  step('Adding upstream remote')
  await git`git remote add upstream ${upstreamUrl}`
}

export function hasGitRepo(repoDir: string) {
  return existsSync(join(repoDir, '.git'))
}

export async function hasStgitStack(repoDir: string, branch: string) {
  const result = await $({ cwd: repoDir, nothrow: true })`git show-ref --verify --quiet refs/stacks/${branch}`
  return result.exitCode === 0
}

export async function getCurrentBranch(repoDir: string) {
  const result = await $({ cwd: repoDir, nothrow: true })`git rev-parse --abbrev-ref HEAD`
  if (result.exitCode !== 0) {
    return null
  }
  return result.stdout.trim()
}

export async function hasLocalBranch(repoDir: string, branch: string) {
  const result = await $({ cwd: repoDir, nothrow: true })`git show-ref --verify --quiet refs/heads/${branch}`
  return result.exitCode === 0
}

async function copyForkDir(repoDir: string, sourceDir: string, repoRelativeTarget: string) {
  const targetDir = join(repoDir, repoRelativeTarget)
  await ensureDir(targetDir)

  // Mirror the source dir into the target: copy every file, remove stale files that no
  // longer exist in the source. Bazel's glob picks up the real files in Sources/ClearGram/.
  const sourceFiles = await fs.readdir(sourceDir, { withFileTypes: true })
  let dirty = false

  for (const entry of sourceFiles) {
    if (!entry.isFile()) continue
    const srcPath = join(sourceDir, entry.name)
    const dstPath = join(targetDir, entry.name)
    const srcContent = await fs.readFile(srcPath)
    const dstContent = await fs.readFile(dstPath).catch(() => null)
    if (!dstContent || !dstContent.equals(srcContent)) {
      step(`Copying ${repoRelativeTarget}/${entry.name}`)
      await fs.writeFile(dstPath, srcContent)
      dirty = true
    }
  }

  // Remove stale files in target that aren't in source.
  const targetFiles = await fs.readdir(targetDir, { withFileTypes: true }).catch(() => [])
  const sourceNames = new Set(sourceFiles.filter(e => e.isFile()).map(e => e.name))
  for (const entry of targetFiles) {
    if (entry.isFile() && !sourceNames.has(entry.name)) {
      step(`Removing stale ${repoRelativeTarget}/${entry.name}`)
      await fs.rm(join(targetDir, entry.name))
      dirty = true
    }
  }

  // git-exclude the whole ClearGram dir so the copied files don't show in git status.
  await ensureGitExclude(repoDir, `${repoRelativeTarget}/`)

  return dirty
}

// Upstream's own app version, straight out of the checkout — the number the official client
// would call itself. Missing/garbled versions.json shouldn't fail a sync, so it degrades.
async function readUpstreamAppVersion(repoDir: string) {
  const raw = await fs.readFile(join(repoDir, 'versions.json'), 'utf8').catch(() => null)
  if (raw === null) {
    warn('versions.json not found — build info will say "unknown" for the Telegram version')
    return 'unknown'
  }
  try {
    const version = (JSON.parse(raw) as { app?: unknown }).app
    return typeof version === 'string' && version.length > 0 ? version : 'unknown'
  } catch {
    warn('versions.json is not valid JSON — build info will say "unknown"')
    return 'unknown'
  }
}

// Everything the working tree adds on top of HEAD, as one patch: the status (so renames and
// deletions register), the tracked diff, and a /dev/null diff per untracked file so new fork
// sources are in there too. null when the tree is clean. worktree/ and node_modules/ are
// gitignored, as is build/, where the patch itself is archived — no feedback loop.
async function collectWorkingTreePatch(git: ReturnType<typeof cd>) {
  const status = await git`git status --porcelain`
  if (status.exitCode !== 0 || status.stdout.trim().length === 0) {
    return null
  }

  const tracked = await git`git diff HEAD`
  const untracked = (await git`git ls-files --others --exclude-standard`)
    .stdout
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)

  // Both git listings are sorted, so the same tree always hashes to the same id.
  const parts = [`# git status --porcelain\n${status.stdout.trimEnd()}\n`, tracked.stdout]
  for (const file of untracked) {
    // Exits 1 because the files differ — that's the diff, not a failure.
    parts.push((await git`git diff --no-index -- /dev/null ${file}`).stdout)
  }
  return parts.join('\n')
}

// cleargram HEAD, plus a `+<id>` suffix when the tree is dirty. The id is a hash of the patch
// above, which makes it an identity and not just a warning light: the same edits always give
// the same id, different edits never collide, and `dirtyPatch` gets archived under that name
// so a build seen on a device can be traced back to exactly what went into it. A counter or a
// timestamp would order builds but tell you nothing about their contents — and a timestamp in
// a Bazel input would also rebuild the module on every single sync.
async function readCleargramCommit() {
  const git = $({ cwd: rootDir, nothrow: true })
  const head = await git`git rev-parse --short HEAD`
  if (head.exitCode !== 0) {
    warn('not a git checkout — build info will say "unknown" for the cleargram commit')
    return { name: 'unknown', dirtyPatch: null }
  }

  const commit = head.stdout.trim()
  const patch = await collectWorkingTreePatch(git)
  if (patch === null) {
    return { name: commit, dirtyPatch: null }
  }
  const id = createHash('sha256').update(patch).digest('hex').slice(0, 7)
  return { name: `${commit}+${id}`, dirtyPatch: patch }
}

// Keep the patch a dirty build was made from, named after the id shown in the app. Lands in
// build/ (gitignored), and an id already on disk is left alone — rebuilding the same tree
// rewrites nothing.
async function archiveDirtyPatch(name: string, patch: string) {
  const target = join(rootDir, dirtyStampsDir, `${name}.diff`)
  if (existsSync(target)) {
    return
  }
  await ensureDir(dirname(target))
  await fs.writeFile(target, patch.endsWith('\n') ? patch : `${patch}\n`)
  step(`Dirty build — archived its patch as ${dirtyStampsDir}/${name}.diff`)
}

// Fill in the build stamp in the worktree, over the placeholder copied from src/. Nothing
// here is derived at build time, so the file only changes when the pin or the commit does.
export async function writeBuildInfo(repoDir: string) {
  const telegramVersion = await readUpstreamAppVersion(repoDir)
  const upstreamCommit = await readPinnedUpstreamCommit()
  const { name: cleargramCommit, dirtyPatch } = await readCleargramCommit()
  if (dirtyPatch !== null) {
    await archiveDirtyPatch(cleargramCommit, dirtyPatch)
  }
  const summary = `Telegram ${telegramVersion} · upstream ${upstreamCommit} · Cleargram ${cleargramCommit}`

  const contents = `// Generated by \`pnpm sync\` (writeBuildInfo in scripts/lib.ts) — do not edit this copy, it is
// overwritten on every sync. The checked-in placeholder it replaces, with the rationale for
// the format, is src/swift/ClearGram/DebugSettingsUI/ClearBuildInfo.swift.

enum ClearBuildInfo {
    // Upstream app version, from worktree/versions.json.
    static let telegramVersion = "${telegramVersion}"
    // The upstream commit the patchset is pinned to (the \`upstream-commit\` file).
    static let upstreamCommit = "${upstreamCommit}"
    // cleargram HEAD when the sources were synced, plus "+<id>" if the tree had uncommitted
    // edits — that id names the patch archived in ${dirtyStampsDir}/.
    static let cleargramCommit = "${cleargramCommit}"

    static let summary = "${summary}"
}
`

  const target = join(repoDir, buildInfoTarget)
  const current = await fs.readFile(target, 'utf8').catch(() => null)
  if (current === contents) {
    return false
  }
  step(`Writing ${buildInfoTarget}`)
  await ensureDir(dirname(target))
  await fs.writeFile(target, contents)
  return true
}

export async function linkForkSource(repoDir: string) {
  let dirty = false
  for (const entry of forkSyncDirs) {
    const sourceDir = resolve(rootDir, entry.source)
    if (!existsSync(sourceDir)) continue
    const created = await copyForkDir(repoDir, sourceDir, entry.target)
    dirty ||= created
  }
  // After the copies, never before: copyForkDir has just laid down the placeholder version
  // of ClearBuildInfo.swift, and this replaces it with the real values. Awaited into its own
  // binding — `dirty ||= await …` would short-circuit and skip the call once dirty is true.
  const stamped = await writeBuildInfo(repoDir)
  return dirty || stamped
}

export async function ensureGitExclude(repoDir: string, repoRelativePath: string) {
  const excludeFile = join(repoDir, '.git', 'info', 'exclude')
  const entry = repoRelativePath.replaceAll('\\', '/')
  const current = await fs.readFile(excludeFile, 'utf8').catch(() => '')
  const lines = current.split(/\r?\n/)

  if (lines.includes(entry)) {
    return
  }

  step(`Adding ${entry} to .git/info/exclude`)
  const next = current.length === 0 || current.endsWith('\n')
    ? `${current}${entry}\n`
    : `${current}\n${entry}\n`
  await fs.writeFile(excludeFile, next)
}

// Idempotently write a managed disk-cache GC block into worktree/.bazelrc. The disk_cache
// path itself comes from Make.py's --cacheDir (passed as --disk_cache to bazel); we only
// pin the GC cap + age here. The block is wrapped in sentinel comments so re-runs replace
// it instead of appending duplicates. Settings are fork-managed (not a patch) — the worktree
// is gitignored, so this never reaches the patchset.
export async function ensureBazelDiskCacheGc(
  repoDir: string,
  maxSizeG: number,
  maxAgeD: number,
) {
  const bazelrc = join(repoDir, '.bazelrc')
  const begin = '# >>> cleargram:disk-cache-gc >>>'
  const end = '# <<< cleargram:disk-cache-gc <<<'
  const block = `${begin}\nbuild --experimental_disk_cache_gc_max_size=${maxSizeG}G\nbuild --experimental_disk_cache_gc_max_age=${maxAgeD}d\n${end}\n`

  const current = await fs.readFile(bazelrc, 'utf8').catch(() => '')
  const beginIdx = current.indexOf(begin)
  if (beginIdx !== -1) {
    const endMarker = current.indexOf(end, beginIdx)
    if (endMarker !== -1) {
      const before = current.slice(0, beginIdx)
      const after = current.slice(endMarker + end.length).replace(/^\n+/, '')
      const next = `${before}${block}${after.length > 0 ? `\n${after}` : ''}`
      if (next !== current) {
        step(`Updating disk-cache GC block in .bazelrc (max ${maxSizeG}G, ${maxAgeD}d)`)
        await fs.writeFile(bazelrc, next)
      }
      return
    }
  }
  const next = current.length === 0 || current.endsWith('\n')
    ? `${current}${block}`
    : `${current}\n${block}`
  step(`Adding disk-cache GC block to .bazelrc (max ${maxSizeG}G, ${maxAgeD}d)`)
  await fs.writeFile(bazelrc, next)
}

function normalizeSeriesLine(line: string) {
  const trimmed = line.trim()
  if (!trimmed) {
    return ''
  }
  return trimmed.replace(/^[+>!-]\s+/, '')
}

async function getPatchNames(repoDir: string, mode: '--applied' | '--all') {
  const stg = cd(repoDir)
  const out = await stg`stg series ${mode}`
  return out.stdout
    .split(/\r?\n/)
    .map(normalizeSeriesLine)
    .map(line => line.trim())
    .filter(Boolean)
}

export async function getAppliedPatchNames(repoDir: string) {
  return await getPatchNames(repoDir, '--applied')
}

export async function getAllPatchNames(repoDir: string) {
  return await getPatchNames(repoDir, '--all')
}

export function patchNameFromSeriesEntry(entry: string) {
  const normalized = entry.trim().replaceAll('\\', '/')
  const match = normalized.match(/^([^/]+)\/(.+)\.patch$/)
  if (!match) {
    throw new Error(`Invalid series entry: ${entry}`)
  }
  return `${match[1]}__${match[2]}`
}

export async function getTopPatch(repoDir: string) {
  const result = await $({ cwd: repoDir, nothrow: true })`stg top`
  if (result.exitCode !== 0) {
    return null
  }
  return result.stdout.trim()
}

export async function getPatchCommitId(repoDir: string, patchName: string) {
  return (await cd(repoDir)`stg id ${patchName}`).stdout.trim()
}

export async function getPatchSubject(repoDir: string, patchName: string) {
  const commitId = await getPatchCommitId(repoDir, patchName)
  return (await cd(repoDir)`git log -1 --format=%s ${commitId}`).stdout.trim()
}

export async function generateStablePatchFromCommit(repoDir: string, commitId: string) {
  const patch = await cd(repoDir)`git format-patch --stdout --zero-commit --no-signature --subject-prefix= -1 ${commitId}`
  return patch.stdout
    .split(/(?=^diff --git )/m)
    .map(section =>
      // Zeroing the index keeps text diffs stable across rebases, but `git apply` refuses a
      // binary hunk without a full 40-hex index pair ("cannot apply binary patch ... without
      // full index line"), which makes such a patch impossible to re-import — it then drops
      // out of the stack on `pnpm setup`/`rebase` and the next export deletes it outright.
      // So binary sections keep their real blob shas; only text sections are zeroed.
      section.includes('GIT binary patch')
        ? section
        : section.replace(/^index [0-9a-f]+\.\.[0-9a-f]+( \d+)?$/gm, 'index 0000000..0000000$1'),
    )
    .join('')
    .replace(/^Subject:.*(?:\n[ \t].*)+/m, m => m.replace(/\n[ \t]+/g, ' '))
}

export async function getAllPatchCommitIds(repoDir: string) {
  const branch = (await cd(repoDir)`git symbolic-ref --short HEAD`).stdout.trim()
  const format = '%(refname) %(objectname)'
  const out = await cd(repoDir)`git for-each-ref --format=${format} refs/patches/${branch}/`
  const prefix = `refs/patches/${branch}/`
  const map = new Map<string, string>()
  for (const line of out.stdout.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed) continue
    const [ref, sha] = trimmed.split(' ')
    if (!ref.startsWith(prefix)) continue
    map.set(ref.slice(prefix.length), sha)
  }
  return map
}

export function parsePatchName(patchName: string) {
  const parts = patchName.split('__').map(part => part.trim()).filter(Boolean)
  if (parts.length !== 2) {
    throw new Error(`Patch name must use "group__name": ${patchName}`)
  }
  const [group, name] = parts
  return {
    group,
    name,
    seriesEntry: `${group}/${name}.patch`,
  }
}

export async function writeSeries(entries: string[]) {
  await fs.writeFile(seriesFile, entries.length > 0 ? `${entries.join('\n')}\n` : '')
  step(`Wrote ${entries.length} ${entries.length === 1 ? 'entry' : 'entries'} to series`)
}

export async function readSeries() {
  const raw = await fs.readFile(seriesFile, 'utf8').catch(() => '')
  return raw
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
}

export async function resolvePatchName(repoDir: string, identifier: string) {
  const patchNames = await getAllPatchNames(repoDir)
  const direct = patchNames.find(patchName => patchName === identifier)
  if (direct) {
    return direct
  }

  const fallback = identifier.includes('/')
    ? patchNames.find(patchName => patchName === identifier.replace('/', '__'))
    : null

  if (fallback) {
    return fallback
  }

  throw new Error(`Unknown patch identifier: ${identifier}`)
}

// Транслирует stgit branch name в worktree-проверки. Экспортируем workBranch для других скриптов.
export { workBranch }
