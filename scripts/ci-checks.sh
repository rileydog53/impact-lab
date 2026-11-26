#!/bin/bash
# Run every CI check, CI_PARALLEL at a time (default 1). Longest checks start first.
# Each check writes its own log in ci-out/; timings go to ci-out/timings.txt. Exit 1 if any check fails.
set -u
N="${CI_PARALLEL:-1}"
mkdir -p ci-out/status
CHECKS=(
  "outline-fracture|ImpactCheck --outline-fracture quick"
  "bend-rig|ImpactCheck --bend-rig quick"
  "locking|ImpactCheck --locking"
  "regression|python3 tests/regression/run.py --out ci-out/regression --skip-build"
  "test-machine|ImpactCheck --test-machine"
  "legacy-replay|ImpactCheck --legacy-replay check docs/legacy-replay-baseline.txt"
  "spall|ImpactCheck --spall"
  "supports-gravity|ImpactCheck --supports-gravity"
  "lab-examples|ImpactCheck --lab-examples"
  "scene-documents|ImpactCheck --scene-documents"
  "taylor-trend|ImpactCheck --taylor-trend"
  "plate-impact|ImpactCheck --plate-impact"
  "plasticity|ImpactCheck --plasticity"
  "assembly-replay|ImpactCheck --assembly-replay"
  "layered-bodies|ImpactCheck --layered-bodies quick"
  "materials|ImpactCheck --materials"
  "bulk-viscosity|ImpactCheck --bulk-viscosity"
  "fracture-guard|ImpactCheck --fracture-guard"
  "metal-profiles|ImpactCheck --metal-profiles"
  "showcases|ImpactCheck --showcases"
  "workshop-improvements|ImpactCheck --workshop-improvements"
  "linked-chain|ImpactCheck run docs/scene-examples/linked-chain.json --out ci-out/headless/linked-chain --timeout 600"
  "metal-plate-vtk|ImpactCheck run docs/scene-examples/metal-plate-impact.json --out ci-out/headless/vtk-metal-plate-impact --timeout 600 --vtk && python3 tests/vtk/check_vtk.py ci-out/headless/vtk-metal-plate-impact"
)
run_one() {
  local name="${1%%|*}" cmd="${1#*|}"
  local start=$(date +%s) status=0
  bash -c "$cmd" > "ci-out/$name.log" 2>&1 || status=$?
  echo "$cmd: $(( $(date +%s) - start )) s (exit $status)" >> ci-out/timings.txt
  echo "$status" > "ci-out/status/$name"
  echo "::group::$cmd (exit $status)"; tail -40 "ci-out/$name.log"; echo "::endgroup::"
}
# CI_TIER=quick (app-UI-only PRs): only the fast checks, a few minutes in all.
if [ "${CI_TIER:-full}" = quick ]; then
  CHECKS=(
    "materials|ImpactCheck --materials" "metal-profiles|ImpactCheck --metal-profiles" "fracture-guard|ImpactCheck --fracture-guard"
    "bulk-viscosity|ImpactCheck --bulk-viscosity" "showcases|ImpactCheck --showcases" "workshop-improvements|ImpactCheck --workshop-improvements"
    "assembly-replay|ImpactCheck --assembly-replay" "layered-bodies|ImpactCheck --layered-bodies quick" "scene-documents|ImpactCheck --scene-documents"
    "linked-chain|ImpactCheck run docs/scene-examples/linked-chain.json --out ci-out/headless/linked-chain --timeout 600"
  )
fi
# Each check is "id|command"; the id names its log and status file. Refuse duplicate or missing ids.
dups=$(printf '%s\n' "${CHECKS[@]}" | cut -d'|' -f1 | sort | uniq -d)
[ -n "$dups" ] && { echo "Duplicate check ids: $dups"; exit 1; }
for c in "${CHECKS[@]}"; do case "$c" in *"|"*) ;; *) echo "Check without id: $c"; exit 1;; esac; done
# Sharding: CI_SHARD=k of CI_SHARDS=n runs only its share. Checks are dealt longest-first to the
# least-loaded shard, using GitHub-hosted durations measured 2026-11-26 (seconds; unknown = 5).
est() {
  case "$1" in
    outline-fracture) echo 437;; bend-rig) echo 301;; locking) echo 179;; spall) echo 125;;
    test-machine) echo 112;; legacy-replay) echo 110;; regression) echo 96;; supports-gravity) echo 56;;
    lab-examples) echo 45;; scene-documents|taylor-trend) echo 16;; plasticity|plate-impact|metal-plate-vtk) echo 10;;
    layered-bodies) echo 8;; assembly-replay) echo 6;; materials) echo 4;; bulk-viscosity) echo 2;; *) echo 5;;
  esac
}
SHARDS="${CI_SHARDS:-1}"; SHARD="${CI_SHARD:-1}"
if [ "$SHARDS" -gt 1 ]; then
  sorted=$(for c in "${CHECKS[@]}"; do echo "$(est "${c%%|*}")	$c"; done | sort -t'	' -k1,1nr | cut -f2-)
  loads=(); for ((i=1; i<=SHARDS; i++)); do loads[$i]=0; done
  mine=()
  while IFS= read -r c; do
    best=1; for ((i=2; i<=SHARDS; i++)); do [ "${loads[$i]}" -lt "${loads[$best]}" ] && best=$i; done
    loads[$best]=$(( ${loads[$best]} + $(est "${c%%|*}") ))
    [ "$best" -eq "$SHARD" ] && mine+=("$c")
  done <<< "$sorted"
  echo "Shard $SHARD of $SHARDS: about ${loads[$SHARD]} s of checks"
  CHECKS=("${mine[@]+"${mine[@]}"}")
fi
echo "Tier ${CI_TIER:-full}: ${#CHECKS[@]} checks, $N at a time"
for c in "${CHECKS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$N" ]; do sleep 2; done
  run_one "$c" &
done
wait
fail=$(grep -lv '^0$' ci-out/status/* 2>/dev/null | wc -l | tr -d ' ')
echo "$fail check(s) failed"; [ "$fail" -eq 0 ]
