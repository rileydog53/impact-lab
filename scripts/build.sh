#!/bin/bash
# Shared local build for Impact Lab. Every checkout and worktree builds into ONE place:
# the main checkout's .build. Usage: scripts/build.sh [swift build|test|run args...]
#   scripts/build.sh build -c release
#   scripts/build.sh test
# ISOLATED=1 scripts/build.sh ...  builds in a throwaway dir that is deleted on exit, even after failure.
set -euo pipefail
src="$(git rev-parse --show-toplevel)"
main="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
scratch="$main/.build"
lock="$main/.git/impactlab-build.lock"
if [ "${ISOLATED:-0}" = 1 ]; then
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/impactlab-iso.XXXXXX")"
  trap 'rm -rf "$scratch"' EXIT INT TERM
else
  # mkdir is atomic: only one task holds the shared build at a time. Stale after 2 h.
  for _ in $(seq 1 720); do
    mkdir "$lock" 2>/dev/null && break
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null || true; continue; fi
    sleep 10
  done
  [ -d "$lock" ] || { echo "build lock busy: $lock" >&2; exit 1; }
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT INT TERM
fi
cmd="${1:-build}"; shift || true
cd "$src"
swift "$cmd" --scratch-path "$scratch" "$@"
