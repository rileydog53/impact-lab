# Impact Lab, agent instructions

## Local build and disk policy (Joseph, 2026-11-25)

The Mac has 16 GB of RAM and a small disk. Build clutter nearly ended the project once, so:

- Prefer cloud CI (GitHub Actions on the PR) over local builds. Build locally only for app smoke tests or when CI cannot answer the question.
- One shared local build location: the main checkout's `.build`. Always build with `scripts/build.sh` (wraps `swift build/test/run --scratch-path <main>/.build` with a lock so concurrent tasks do not corrupt it). Never run a bare `swift build` inside a worktree, and never create `.build-*` copies.
- Worktrees hold source only. Remove a worktree (`git worktree remove`) as soon as its branch is pushed.
- If an isolated build is truly needed, use `ISOLATED=1 scripts/build.sh ...`; it builds in a temp dir that is deleted on exit, including after a failure. Say in your report why it was needed.
- No review clones, test copies or extra `.app` bundles. Keep one current app build. Delete scratch/temp output before ending the task.
