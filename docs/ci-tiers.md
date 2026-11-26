# CI test tiers (approved by Joseph, 2026-11-25)

The `build and checks` job picks a tier from the files a pull request changes:

| Tier | When | What runs |
|---|---|---|
| docs | only `docs/`, `research/`, `reports/`, `*.md`, `LICENSE` changed | nothing; the check passes so merges aren't blocked |
| quick | only the app UI (`Sources/ImpactLab/`) plus docs changed. No check target depends on it | release build + 10 fast checks |
| full | anything else (solver, physics, geometry, checks, scenes, CI), manual runs. Pushes to `main` use the same rules on everything since the previous main commit | every check, including replay regressions |

When unsure, the job uses the full suite. Checks are listed in `scripts/ci-checks.sh`.

## Joseph's Mac runner
- Label `impactlab-mac`, installed in `~/actions-runner`, launchd agent `com.impactlab.runner` (not started at login).
- Used only for this repo's own branches, and only while repo variable `IMPACTLAB_MAC` is `on` (or a manual run with `mac: true`).
- Takes a run only when free; a busy or offline Mac sends the run to GitHub-hosted macOS (no repo-wide queue). Runs 3 checks at a time; GitHub-hosted runs 1 at a time.
- Keeps one SwiftPM build cache in `~/actions-runner/spm-cache`, wiped by the after-job hook only past 6 GB. The disk rule targets unmanaged clutter, so don't delete this cache.
- Stop: `launchctl bootout gui/$(id -u)/com.impactlab.runner`

The full and quick tiers split into 3 shards that run side by side (`checks shard 1..3`), balanced by measured durations in `scripts/ci-checks.sh`. Shard 1 uses the Mac when it is free. The summary check `build and checks` passes only when every shard passed.
