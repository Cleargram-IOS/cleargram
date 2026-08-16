import { existsSync } from 'node:fs'
import fs from 'node:fs/promises'
import { isAbsolute, join, relative, resolve } from 'node:path'
import { $, chalk } from 'zx'
import {
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

export async function linkForkSource(repoDir: string) {
  let dirty = false
  for (const entry of forkSyncDirs) {
    const sourceDir = resolve(rootDir, entry.source)
    if (!existsSync(sourceDir)) continue
    const created = await copyForkDir(repoDir, sourceDir, entry.target)
    dirty ||= created
  }
  return dirty
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
