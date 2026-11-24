> COPY made 2026-11-24 for preservation. Original: research/beam-verification/RESULTS.md on Joseph's Mac (untracked). The original wins if they differ.

# Beam-bending verification: constant-strain-triangle (CST) convergence

Status labels: **verified** = reproduced by a run in this folder; **agent-reported** = from memory/textbook, not independently checked; **hypothesis** = untested explanation.

## Setup (verified)
- Code: unmodified `ImpactPhysics` copied from main at the commit in `SOURCE_COMMIT.txt` into this folder (the solver's step function is `internal`, so an external package cannot call it; the copy only adds `BeamHarness.swift`). No tracked file was edited.
- Test: free-free beam, L = 1 m, h = 0.05 m (L/h = 20), E = 1 MPa, rho = 1000 kg/m^3, nu = 0, unit width, elastic, no contact. Initial velocity = first Euler-Bernoulli free-free mode shape, amplitude 1e-4. Centre-node vertical position tracked; period from upward zero crossings over 3-4 cycles. Square cells (columns = 20 x rows).
- Reference: Euler-Bernoulli period 0.61528 s (`reference_calculator.py`, matches the Swift value to 5 digits). Approximate Timoshenko correction 0.62013 s (+0.8%; agent-reported formula).

## Results (verified, single run each)
| rows through thickness | triangles | alternating diagonals, period error vs EB | staggered diagonals |
|---|---|---|---|
| 2 | 160 | -23.4% | -26.0% |
| 4 | 640 | -7.4% | -8.6% |
| 8 | 2560 | -1.4% | -1.8% |
| 16 | 10240 | +0.26% | +0.16% |

Energy drift stayed below 1.6e-4 relative in all runs. Wall time 0.2 s to 105 s.

## Interpretation
- **Verified:** the solver's beam is too stiff (period too short) on coarse meshes, i.e. the known CST bending over-stiffness is real and large: with 4 rows the first bending period is 7% off, with 2 rows 23%.
- **Verified:** change between successive refinements is 4->8 about 6 points, 8->16 about 1.7 points, so the PLAN gate A3 criterion (under 5% change on the final refinement) is met from 8->16 here, and an absolute error under 5% needs about 8 rows for L/h = 20.
- **Hypothesis:** the small positive error at 16 rows (and the near-tie between mesh patterns) is the lumped-mass frequency lowering partly cancelling the CST stiffening, plus the Timoshenko effect (~0.8%) that Euler-Bernoulli ignores. Against the Timoshenko-corrected reference the 16-row error is about -0.5%. Not separated by a dedicated test.
- **Scope limit:** this is a numerical verification of the elastic bending stiffness/inertia only (free vibration, thin beam, nu = 0). It does not cover thick beams, nu != 0 (plane stress vs plane strain convention should be checked), locking near incompressibility, static loading, or contact. It is not physical validation, and Joseph has not accepted any threshold.

## Reproduce
```
cd research/beam-verification && swift build -c release
.build/release/BeamStudy 2,4,8      # about 30 s; add 16 for another ~3.5 min
python3 reference_calculator.py --selftest
```
Original run output: `results_free_free_beam_rows2-8.txt`.
