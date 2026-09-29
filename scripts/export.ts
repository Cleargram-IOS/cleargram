import fs from 'node:fs/promises'
import { join, relative } from 'node:path'
import { parallelMap } from '@fuman/utils'
import { patchesDir, rootDir, worktreeDir } from './config.js'
import {
  cd,
  ensureDir,
  generateStablePatchFromCommit,
  getAllPatchCommitIds,
  getAppliedPatchNames,
  parsePatchName,
  resolveFromRoot,
  step,
  success,
  warn,
  writeSeries,
} from './lib.js'

async function listFilesRecursive(dir: string): Promise<string[]> {
  const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => [])
  const files: string[] = []

  for (const entry of entries) {
    const fullPath = join(dir, entry.name)
    if (entry.isDirectory()) {
      files.push(...await listFilesRecursive(fullPath))
      continue
    }
    files.push(fullPath)
  }

  return files
}

async function clearExportedPatchFiles() {
  for (const file of await listFilesRecursive(patchesDir)) {
    if (file.endsWith('.patch')) {
      await fs.unlink(file)
    }
  }
}

async function exportPatchFile(repoDir: string, patchName: string, commitId: string) {
  const parsed = parsePatchName(patchName)
  const git = cd(repoDir)

  const files = (await git`git diff-tree --no-commit-id --name-only -r ${commitId}`)
    .stdout
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)

  if (files.length === 0) {
    warn(`Patch ${patchName} is empty`)
  }

  const targetDir = join(patchesDir, parsed.group)
  const targetFile = join(targetDir, `${parsed.name}.patch`)
  await ensureDir(targetDir)

  step(`Exporting ${patchName} -> ${relative(rootDir, targetFile)}`)
  const stable = await generateStablePatchFromCommit(repoDir, commitId)
  await fs.writeFile(targetFile, stable)

  return parsed
}

const repoDir = resolveFromRoot(process.argv[2], worktreeDir)

const dirty = (await cd(repoDir)`git status --porcelain`).stdout.trim()
if (dirty) {
  warn(`Worktree has uncommitted changes:\n${dirty}`)
}

const [patchNames, commitIds] = await Promise.all([
  getAppliedPatchNames(repoDir),
  getAllPatchCommitIds(repoDir),
])
await clearExportedPatchFiles()

// `local__*` patches are machine-specific by definition — dev signing (bundle id, team id),
// build flags a free Apple ID needs. They stay in the stgit stack and out of the repo, which is
// also what `check-patches.ts` assumes: it keeps a separate baseline for them precisely because
// they "never reach patches/". Without this filter an export drops them into `patches/local/` and
// lists them in `series`, so the next commit carries them and a fresh `pnpm setup` elsewhere tries
// to apply patches that do not exist.
const exportable = patchNames.filter(name => parsePatchName(name).group !== 'local')
const skipped = patchNames.length - exportable.length
if (skipped > 0) {
  step(`Skipping ${skipped} local ${skipped === 1 ? 'patch' : 'patches'} (never exported)`)
}

const entries = await parallelMap(exportable, async (patchName) => {
  const commitId = commitIds.get(patchName)
  if (!commitId) throw new Error(`No commit id for applied patch ${patchName}`)
  const patch = await exportPatchFile(repoDir, patchName, commitId)
  return patch.seriesEntry
})

await writeSeries(entries)

// warn again because it might get lost in logs
if (dirty) {
  warn(`Worktree has uncommitted changes:\n${dirty}`)
}

success(`Exported ${entries.length} ${entries.length === 1 ? 'patch' : 'patches'}`)
