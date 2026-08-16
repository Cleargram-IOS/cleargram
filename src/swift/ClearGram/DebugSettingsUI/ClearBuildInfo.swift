// Which build this is, shown as the last line of Cleargram Settings.
//
// Cleargram has no version of its own on purpose. What identifies a build is the upstream
// release it is pinned to plus the two commits it was assembled from — that needs no state
// to maintain and maps straight back to the source, which a build counter doesn't.
//
// A build made from a dirty tree gets a "+<id>" suffix on the cleargram commit, where the id
// hashes the working-tree patch, and `pnpm sync` archives that patch as
// build/dirty-stamps/<commit>+<id>.diff. So the line stays an identity even when it doesn't
// name a commit: identical trees give identical ids, and the diff behind any id you see on a
// device is still on disk (`git apply` puts it back).
//
// The values below are placeholders. `pnpm sync` copies this file into the worktree like any
// other fork source and then overwrites the copy with the real ones (`writeBuildInfo` in
// scripts/lib.ts) — so the symbol always exists and the build can't break on a sync that
// didn't run, while "unknown" in the UI says the stamp wasn't written. Don't put build-time
// values (a timestamp) in here: this is a Bazel input, and it should only change when the
// pin or the commit does.

enum ClearBuildInfo {
    // Upstream app version, from worktree/versions.json.
    static let telegramVersion = "unknown"
    // The upstream commit the patchset is pinned to (the `upstream-commit` file).
    static let upstreamCommit = "unknown"
    // cleargram HEAD when the sources were synced, plus "+<id>" if the tree had uncommitted
    // edits — that id names the patch archived in build/dirty-stamps/.
    static let cleargramCommit = "unknown"

    static let summary = "Telegram \(telegramVersion) · upstream \(upstreamCommit) · Cleargram \(cleargramCommit)"
}
