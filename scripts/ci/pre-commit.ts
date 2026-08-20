import { chalk } from 'zx'
import { checkPatches, printReport } from '../check-patches.js'

// patches/ must match the stgit stack at commit time, or the commit records an export that no
// longer describes the stack. The check itself lives in scripts/check-patches.ts, which build.sh
// also runs before building — the difference is that this one leaves `local__*` patches alone:
// they are never exported, so on a commit there is nothing about them to be out of sync.

if (process.env.SKIP_PATCH_CHECK) {
  process.exit(0)
}

const report = await checkPatches({ includeLocal: false })
if (report.ok) {
  process.exit(0)
}

printReport(report)
console.error()
console.error(chalk.yellow('hint: run `pnpm export` to refresh,'))
console.error(chalk.yellow('      or skip this check entirely via --no-verify'))
process.exit(1)
