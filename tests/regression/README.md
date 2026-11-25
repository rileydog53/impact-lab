# Regression and usability suite

Automated, offline, reproducible checks of ordinary lab experiments, run through the unmodified solver.
**Numerical verification only.** It is not physical validation, and no threshold here has been accepted by Joseph.

```
python3 tests/regression/run.py                 # build, run (~6 min with a clean build, ~3 min after), compare, write report
python3 tests/regression/run.py --skip-build    # reuse .build-regression
python3 tests/regression/run.py --reuse DIR     # re-judge an earlier harness output
python3 tests/regression/run.py --record-baseline   # only after a deliberate, reviewed solver change
```
Output (`report.md`, `results.json`, `measurements.json`, `usability.json`, `harness.log`) goes to `$TMPDIR/impactlab-regression` or `--out`, never into tracked files. Exit status is 1 on any FAIL.

## Parts
- `Sources/ImpactRegression` — a new executable target that only uses the solver's public API. It records measurements; it judges nothing.
- `tests/regression/run.py` — references, tolerances, baseline comparison, report. `CHECKS` lists every tolerance and says whether it is the same criterion as an existing ImpactCheck gate ("existing") or introduced here ("new"). No existing criterion was loosened.
- `tests/regression/reference_calculator.py` — copy of `research/beam-verification/reference_calculator.py` (Timoshenko-corrected clamped-free beam frequency). Textbook closed forms; labelled agent-reported there.
- `tests/regression/baseline.json` — recorded measurements (wall time excluded). Drift tolerance 1e-6 relative; on this Mac a clean rebuild reproduced every value exactly.

## Experiments
| experiment | source | analytic reference / invariant |
|---|---|---|
| block_on_bench | docs/lab-examples | impulse–momentum balance; energy drift |
| drop_test | docs/lab-examples | free fall y0 − g t²/2; KE = m g h at contact; rebound recorded as illustrative |
| cantilever_sag | docs/lab-examples | Timoshenko static sag (5%), first-mode period (5%), peak ≈ 2× mean |
| bar_vibration_x2, _x4 | new (same bar, 0.55 s, two meshes) | first-mode period from 9 troughs; shows mesh convergence (x2 −3.7%, x4 −0.4%) |
| three_point_bend | docs/lab-examples | impulse balance; energy; peak deflection baseline |
| hanging_springs | docs/lab-examples | period 2π√(m/k), mean drop m g/k, peak 2 m g/k; preloaded block stays still |
| stack_on_support | new (two blocks on a fixed bench) | reaction = total weight (1%); lateral drift < 0.01 mm; impulse balance |
| stack_offset | new (upper block 4 mm off centre) | informational |
| determinism | new | same scene twice, positions identical bit for bit |
| layered_two_region | new (layered target plan step 2: plastic copper layer bonded to elastic steel in one body) | energy error < 0.5% |
| layered_bond_pull | new (plan step 3: two-layer bar pulled apart, weak cohesive bond) | fracture dissipation = bond toughness × bond length (2%); no cracks off the bond; whole 30 mm bond fails |

The impulse balance (support reaction impulse = weight impulse + change in momentum of the free bodies) agrees to about 1e-12 everywhere. That is a bookkeeping-consistency check on the solver's support reactions, not independent evidence of material accuracy; it would catch a broken support, gravity or momentum accounting.

## Findings (verified = reproduced in this suite; hypothesis = not tested)
1. **Verified, documentation wording.** block-on-bench says the time-averaged bench reaction equals the weight. Averaged over the second half of the run it is 0.980 of the weight, because the block is still moving; the exact statement is reaction impulse = weight impulse + Δmomentum (agrees to 1e-13 over the same window). Not a solver error.
2. **Verified, no discrepancy found** in any other reference: cantilever sag −2.1% and period −0.4% (x4 mesh), hanging-spring period +0.06%, free fall exact to 1e-13 m.
3. **Verified, expected CST behaviour:** the coarse (×2) bar's first period is 3.7% short; the tolerance (5%) is met on ×4 only. Consistent with research/beam-verification.
4. **Verified:** 4 mm off-centre upper block slides 0.016 mm on a frictionless interface over 0.3 s (centred: 0.0008 mm). Small; recorded, not a criterion.
5. **Verified:** the run-cost estimate is within 5% of measured time for two examples (claim: factor two).
6. **Hypothesis:** drop-test rebound (0.96 of drop height) depends on contact penalty and mesh; kept INFO as the example itself says.

## Usability rough spots (verbatim messages in `usability.json` / report.md)
- A scene file with no bodies (`{}`) loads without complaint; nothing says it has nothing to run.
- Hand-written material `provenance` with a wrong shape gives only "The scene structure could not be read." (a profile name string gives a good, listing message).
- Overlapping bodies load fine and are refused only when the run starts, with good wording ("Leave a small clearance"); the file loader could say so earlier.
- Reaction/weight wording in the block-on-bench description (finding 1).
- Good as is: truncated/invalid JSON, out-of-range values (name, value, allowed range, unit), misspelt keys ("did you mean gravity?"), friction/restitution requests (explains why), units in mm (50 m caught, both fields listed).
- Not tested here: the app UI itself, and the uncommitted AssemblyAdvisories (bendingAdvisory) that exist only in the main working tree, not on `main`.
