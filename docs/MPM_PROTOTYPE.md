# Alternative backend prototype: 2-D MPM (2026-11-23)

This is a bounded experiment. The app and the FEM solver are unchanged. The prototype lives in [`Sources/ImpactPhysics/MPMPrototype.swift`](../Sources/ImpactPhysics/MPMPrototype.swift) (about 250 lines) and is driven by `ImpactCheck --mpm-compare` ([`Sources/ImpactCheck/MPMComparison.swift`](../Sources/ImpactCheck/MPMComparison.swift)).

## What was built

The prototype is an explicit plane-strain material point method:
- **Transfers:** MLS-MPM with APIC transfers, on quadratic B-splines.
- **Particles:** 2 × 2 particles per cell.
- **Timestep:** a CFL of 0.3, based on the P-wave speed plus particle speed.
- **Wall:** a stationary frictionless rigid wall, imposed on grid nodes.
- **Material law:** each particle calls the FEM's own verified Hencky–J2 routine (`J2Model.update`, with the tabulated C11000 copper hardening). Both methods therefore use the identical material law and energy convention, and any difference comes from the discretisation.

## The shared test

A plane-strain copper block, 40 × 25 mm, strikes a frictionless rigid wall. FEM solves the identical problem by symmetry: two mirror-image blocks collide head-on with frictionless contact. Results below are per block, in J/m. Times are measured from first contact. The finest FEM mesh is ×7 (1,176 triangles per block). The finest MPM grid is dx 0.25 mm (64,000 particles).

| Regime | Quantity | FEM (×7) | MPM (finest) |
|---|---|---:|---:|
| Elastic, 5 m/s, 100 µs | rebound speed | 4.06 m/s | 4.07 m/s |
| | kinetic / stored energy | 83.9 / 27.5 | 83.5 / 25.5 |
| | contact duration (1-D estimate 20.8 µs) | 21.2 µs | 21.3 µs at dx 1 mm; force-threshold tail at finer grids |
| | energy error | 0.03% | 2.2% (13.5 → 7.9 → 4.4 → 2.2% as dx halves) |
| Plastic, 50 m/s, 300 µs | plastic work | 4,689 | 4,660 (−0.6%) |
| | final length / impact-face width | 38.35 / 29.03 mm | 38.16 / 29.16 mm |
| | peak plastic strain | 27.1% | 26.1% |
| | energy error / wall time | 0.02% / 6.3 s | 0.86% / 157 s (dx 0.5 mm: 1.7% / 20 s) |
| Severe, 150 m/s, 300 µs | plastic work | 32,657 | 31,813 (dx 0.5 mm) |
| | final length / face width | 28.44 / 45.14 mm | 28.12 / 47.95 mm |
| | peak plastic strain | 168% | 200% |
| | energy error | 0.03% | 2.8% |
| Short block, 25 × 60 mm, 150 m/s | length / face width / peak εp | 24.07 / 90.8 mm / 89% | 23.28 / 91.9 mm / 69% |

**Beyond FEM's reach in the app.** The app's validation caps speed at 150 m/s, so FEM was not run here. The MPM was:

| MPM only | Result |
|---|---|
| 300 m/s, 200 µs | The block flattens to 12.5 mm long. Peak plastic strain 340–385%, with the face width still mesh-dependent (58 → 64 mm). Energy error 7.4% → 5.9%. |
| 600 m/s, 150 µs | Sideways jets spread over 300 mm, peak plastic strain 430–590%, energy error about 10%. The run stopped when material left the background grid. Nothing tangled or inverted. |

Reproduce with commands such as `ImpactCheck --mpm-compare plastic 50 300 2,4,7 1,0.5,0.25`. The arguments are: regime, speed in m/s, duration in µs, FEM mesh levels, MPM spacings in mm, and an optional block size such as `25x60` in mm.

## What the numbers say

1. **The two methods agree where both apply.** Elastic rebound agrees within 0.3%. At 50 m/s, plastic work agrees within 0.6% and the final shape within about 0.5 mm. The prototype therefore works, and it confirms the FEM independently with a different spatial method.
2. **FEM is more accurate and much cheaper up to the app's limit.** At 150 m/s and 168% plastic strain, FEM still conserves energy to 0.03% and its mesh did not fail. MPM's error is first-order: 1–3% at practical grid sizes, and 6–10% in the extreme runs. MPM also needs 4–25 times the compute time for comparable answers.
3. **MPM's contact is a weak point.** A grid-based wall or contact acts about 1.5 cells early. Loss of contact is smeared. Bodies sharing one grid stick together, so separating bodies, sliding and rebound are less trustworthy than FEM's penalty contact. In the plastic runs, MPM's lower rebound speed (−3.8 vs −4.0 m/s) and its later loss of wall force are partly this effect.
4. **MPM's real advantage appears only beyond today's envelope.** It ran to 300–600 m/s and strains of several hundred percent without tangling. The physics there is not credible, though: the model has no rate or thermal softening, no equation of state, and no failure.

## Recommendation

**Keep FEM as Impact Lab's solver. Do not replace it with MPM now.** In every regime the app can express, FEM is as good or better, and cheaper. Keep the MPM prototype as a research tool and cross-check, not a product feature.

If extreme deformation becomes a real goal, these are the steps, in order:
1. **Measure where FEM actually breaks.** Raise the 150 m/s cap in a test-only path. FEM did not fail at the cap, and finding its true limit is cheap.
2. **Add physics before switching solvers.** A material failure or damage model, plus rate and temperature effects, are prerequisites for meaningful severe-impact results with either method.
3. **Then improve MPM, if still needed.** If the FEM limit is the blocker, upgrade MPM before connecting it to the app: give each body its own grid velocity for contact (multi-field), and switch to a less diffusive particle-domain variant such as CPDI.

**Limits of this prototype.**
- It supports only rectangles and discs, with no app integration.
- It runs single-threaded.
- It has one shared grid, with only the frictionless rigid wall as a boundary.
- It was compared on one problem family only.
