import fs from 'node:fs/promises'
import { join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parallelMap } from '@fuman/utils'
import { chalk } from 'zx'
import { localPatchBaselineFile, patchesDir, rootDir, worktreeDir } from './config.js'
import {
  cd,
  generateStablePatchFromCommit,
  getAllPatchCommitIds,
  getAllPatchNames,
  getAppliedPatchNames,
  parsePatchName,
} from './lib.js'

// Is patches/ still what the stgit stack says it is?
//
// The failure this exists for: a stack move (`stg push`/`pop`/`goto` without `-k`, or a bare
// `stg refresh`) folds an uncommitted worktree into whatever patch happens to be on top. The
// work is not lost, it is just attributed to the wrong patch — and if that patch is a
// `local__*` one, `pnpm export` drops it on the floor and it looks like the work vanished.
//
// Two halves, because the two kinds of patch have different ground truth:
//   - real patches are exported, so patches/ is the answer and any difference is drift;
//   - local patches are deliberately never exported, so there is nothing in the repo to compare
//     against. The check keeps its own baseline of their file lists instead and reports what
//     changed since it last ran clean.

const isLocal = (seriesEntry: string) => seriesEntry.startsWith('local/')

export interface LocalPatchChange {
  patch: string
  added: string[]
  removed: string[]
}

export interface PatchCheckReport {
  missing: string[]
  orphaned: string[]
  drifted: string[]
  localChanged: LocalPatchChange[]
  /** Local patches seen for the first time — recorded, not a problem. */
  localRecorded: string[]
  ok: boolean
}

async function listExportedPatchFiles(): Promise<string[]> {
  const out: string[] = []
  const walk = async (dir: string) => {
    const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => [])
    for (const entry of entries) {
      const full = join(dir, entry.name)
      if (entry.isDirectory()) {
        await walk(full)
      } else if (entry.name.endsWith('.patch')) {
        out.push(full)
      }
    }
  }
  await walk(patchesDir)
  return out
}

async function getPatchFiles(repoDir: string, commitId: string): Promise<string[]> {
  const out = await cd(repoDir)`git show --name-only --format= ${commitId}`
  return out.stdout.split(/\r?\n/).map(line => line.trim()).filter(Boolean).sort()
}

type Baseline = Record<string, string[]>

async function readBaseline(): Promise<Baseline> {
  const raw = await fs.readFile(join(rootDir, localPatchBaselineFile), 'utf8').catch(() => null)
  if (!raw) return {}
  try {
    const parsed = JSON.parse(raw)
    return typeof parsed === 'object' && parsed !== null ? parsed as Baseline : {}
  } catch {
    return {}
  }
}

async function writeBaseline(baseline: Baseline) {
  const target = join(rootDir, localPatchBaselineFile)
  await fs.mkdir(join(target, '..'), { recursive: true })
  await fs.writeFile(target, `${JSON.stringify(baseline, null, 2)}\n`)
}

export async function checkPatches(options: { includeLocal: boolean, acceptLocal?: boolean }): Promise<PatchCheckReport> {
  const [applied, all, commitIds] = await Promise.all([
    getAppliedPatchNames(worktreeDir),
    getAllPatchNames(worktreeDir),
    getAllPatchCommitIds(worktreeDir),
  ])

  // Drift is only meaningful for applied patches — an unapplied one is not part of what the
  // export describes.
  const expected = new Map<string, { patchName: string, commitId: string }>()
  for (const name of applied) {
    const { seriesEntry } = parsePatchName(name)
    if (isLocal(seriesEntry)) continue
    const commitId = commitIds.get(name)
    if (!commitId) throw new Error(`No commit id for applied patch ${name}`)
    expected.set(seriesEntry, { patchName: name, commitId })
  }

  // Local patches are scanned whether or not they are applied. They spend most of their life
  // popped — the usual order is build (pushes them), then export/commit (pops them) — so a check
  // that only looked at applied patches would miss the contamination on every run but one.
  const localPatches: { patchName: string, commitId: string }[] = []
  for (const name of all) {
    if (!isLocal(parsePatchName(name).seriesEntry)) continue
    const commitId = commitIds.get(name)
    if (!commitId) continue
    localPatches.push({ patchName: name, commitId })
  }

  const exportedEntries = new Set(
    (await listExportedPatchFiles())
      .map(f => relative(patchesDir, f).replaceAll('\\', '/'))
      .filter(entry => !isLocal(entry)),
  )

  const missing: string[] = []
  const drifted: string[] = []
  const orphaned: string[] = []

  const checks = await parallelMap(
    [...expected],
    async ([entry, { patchName, commitId }]) => {
      if (!exportedEntries.has(entry)) {
        return { kind: 'missing' as const, entry, patchName }
      }
      const [actual, stable] = await Promise.all([
        fs.readFile(join(patchesDir, entry), 'utf8'),
        generateStablePatchFromCommit(worktreeDir, commitId),
      ])
      return { kind: actual === stable ? 'ok' as const : 'drift' as const, entry, patchName }
    },
  )

  for (const r of checks) {
    if (r.kind === 'missing') missing.push(`${r.patchName} (expected patches/${r.entry})`)
    else if (r.kind === 'drift') drifted.push(`${r.patchName} (patches/${r.entry})`)
  }

  for (const entry of exportedEntries) {
    if (!expected.has(entry)) orphaned.push(`patches/${entry}`)
  }

  const localChanged: LocalPatchChange[] = []
  const localRecorded: string[] = []

  if (options.includeLocal && localPatches.length > 0) {
    const baseline = await readBaseline()
    const next: Baseline = { ...baseline }

    for (const { patchName, commitId } of localPatches) {
      const files = await getPatchFiles(worktreeDir, commitId)
      const known = baseline[patchName]
      if (!known || options.acceptLocal) {
        // First sighting (or an explicit re-baseline): record and stay quiet. A patch that was
        // already contaminated when the baseline was first written stays invisible — the only
        // cure for that is looking at it once, which is what --accept-local is for.
        next[patchName] = files
        if (!known) localRecorded.push(patchName)
        continue
      }
      const added = files.filter(f => !known.includes(f))
      const removed = known.filter(f => !files.includes(f))
      if (added.length === 0 && removed.length === 0) continue
      localChanged.push({ patch: patchName, added, removed })
      // Deliberately not updated: the warning must survive until it is dealt with.
    }

    await writeBaseline(next)
  }

  return {
    missing,
    orphaned,
    drifted,
    localChanged,
    localRecorded,
    ok: missing.length === 0 && orphaned.length === 0 && drifted.length === 0 && localChanged.length === 0,
  }
}

export function printReport(report: PatchCheckReport) {
  const print = (label: string, items: string[]) => {
    if (items.length === 0) return
    console.error(chalk.red(`${label}:`))
    for (const item of items) console.error(`  - ${item}`)
  }

  if (report.missing.length || report.orphaned.length || report.drifted.length) {
    console.error(chalk.red('patches/ is out of sync with the stgit stack:'))
    print('missing from patches/', report.missing)
    print('not in stgit stack', report.orphaned)
    print('content drift', report.drifted)
  }

  for (const change of report.localChanged) {
    console.error(chalk.red(`${change.patch} is not what it was:`))
    for (const file of change.added) console.error(`  ${chalk.red('+')} ${file}`)
    for (const file of change.removed) console.error(`  ${chalk.yellow('-')} ${file}`)
    console.error(chalk.yellow('  local patches are never exported — anything that landed here is dropped by `pnpm export`'))
  }
}

// CLI. The path comparison goes through fileURLToPath because import.meta.url percent-encodes
// the space in "Xcode Projects", and a naive `file://${argv[1]}` never matches.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = new Set(process.argv.slice(2))
  const report = await checkPatches({
    includeLocal: args.has('--include-local') || args.has('--accept-local'),
    acceptLocal: args.has('--accept-local'),
  })

  if (report.localRecorded.length > 0 && !args.has('--quiet')) {
    console.error(chalk.gray(`recorded baseline for: ${report.localRecorded.join(', ')}`))
  }

  if (report.ok) {
    if (!args.has('--quiet')) console.log(chalk.green('patches are in sync'))
    process.exit(0)
  }

  printReport(report)
  console.error()
  console.error(chalk.yellow('hint: `pnpm export` refreshes patches/ from the stack;'))
  console.error(chalk.yellow('      a patch holding files it should not means a stack move swallowed'))
  console.error(chalk.yellow('      your worktree — see AGENTS.md, golden rule 2'))
  process.exit(1)
}
