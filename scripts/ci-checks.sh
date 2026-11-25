#!/bin/bash
# Run every CI check, CI_PARALLEL at a time (default 1). Longest checks start first.
# Each check writes its own log in ci-out/; timings go to ci-out/timings.txt. Exit 1 if any check fails.
set -u
N="${CI_PARALLEL:-1}"
mkdir -p ci-out/status
CHECKS=(
  "ImpactCheck --outline-fracture quick"
  "ImpactCheck --bend-rig quick"
  "ImpactCheck --locking"
  "python3 tests/regression/run.py --out ci-out/regression --skip-build"
  "ImpactCheck --test-machine"
  "ImpactCheck --legacy-replay check docs/legacy-replay-baseline.txt"
  "ImpactCheck --spall"
  "ImpactCheck --supports-gravity"
  "ImpactCheck --lab-examples"
  "ImpactCheck --scene-documents"
  "ImpactCheck --taylor-trend"
  "ImpactCheck run docs/showcase/brittle-tile-fracture.json --out ci-out/headless/brittle-tile-fracture --timeout 600"
  "ImpactCheck --plate-impact"
  "ImpactCheck --plasticity"
  "ImpactCheck run docs/scene-examples/metal-plate-impact.json --out ci-out/headless/metal-plate-impact --timeout 600"
  "ImpactCheck --assembly-replay"
  "ImpactCheck --layered-bodies quick"
  "ImpactCheck --materials"
  "ImpactCheck --bulk-viscosity"
  "ImpactCheck --fracture-guard"
  "ImpactCheck --metal-profiles"
  "ImpactCheck --showcases"
  "ImpactCheck --workshop-improvements"
  "ImpactCheck run docs/scene-examples/linked-chain.json --out ci-out/headless/linked-chain --timeout 600"
  "ImpactCheck run docs/scene-examples/metal-plate-impact.json --out ci-out/headless/vtk-metal-plate-impact --timeout 600 --vtk && python3 tests/vtk/check_vtk.py ci-out/headless/vtk-metal-plate-impact"
)
run_one() {
  local cmd="$1" name; name=$(echo "$cmd" | cut -c1-60 | tr -c 'A-Za-z0-9\n' '_')
  local start=$(date +%s) status=0
  bash -c "$cmd" > "ci-out/$name.log" 2>&1 || status=$?
  echo "$cmd: $(( $(date +%s) - start )) s (exit $status)" >> ci-out/timings.txt
  echo "$status" > "ci-out/status/$name"
  echo "::group::$cmd (exit $status)"; tail -40 "ci-out/$name.log"; echo "::endgroup::"
}
# CI_TIER=quick (app-UI-only PRs): only the fast checks, a few minutes in all.
if [ "${CI_TIER:-full}" = quick ]; then
  CHECKS=(
    "ImpactCheck --materials" "ImpactCheck --metal-profiles" "ImpactCheck --fracture-guard"
    "ImpactCheck --bulk-viscosity" "ImpactCheck --showcases" "ImpactCheck --workshop-improvements"
    "ImpactCheck --assembly-replay" "ImpactCheck --layered-bodies quick" "ImpactCheck --scene-documents"
    "ImpactCheck run docs/scene-examples/linked-chain.json --out ci-out/headless/linked-chain --timeout 600"
  )
fi
echo "Tier ${CI_TIER:-full}: ${#CHECKS[@]} checks, $N at a time"
for c in "${CHECKS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$N" ]; do sleep 2; done
  run_one "$c" &
done
wait
fail=$(grep -lv '^0$' ci-out/status/* 2>/dev/null | wc -l | tr -d ' ')
echo "$fail check(s) failed"; [ "$fail" -eq 0 ]
